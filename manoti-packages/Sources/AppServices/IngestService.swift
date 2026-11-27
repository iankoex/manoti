//
//  IngestService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import CryptoKit
import Foundation
import Observation
import SwiftData

nonisolated public struct IngestOutcome: Sendable, Equatable {
    public enum Status: String, Sendable {
        case recorded
        case duplicate
        case needsReview
        case unrecognised
        case ignored
    }

    public let status: Status
    public let entryID: UUID?
    public let unparsedID: UUID?
    public let summary: String

    public init(status: Status, entryID: UUID?, unparsedID: UUID? = nil, summary: String) {
        self.status = status
        self.entryID = entryID
        self.unparsedID = unparsedID
        self.summary = summary
    }
}

/// Turns a raw bank or mobile money message into a ledger entry, or refuses to guess.
@Observable
nonisolated public final class IngestService: Loggable {
    private let context: ModelContext
    private let parser: ParserService
    private let accountService: AccountService

    public init(context: ModelContext) {
        self.context = context
        self.parser = ParserService(context: context)
        self.accountService = AccountService(context: context)
    }

    @discardableResult
    public func ingest(text: String, sender: String? = nil, receivedAt: Date = Date()) throws -> IngestOutcome {
        let outcome: ParseOutcome
        do {
            outcome = try parser.parse(text: text, sender: sender, receivedAt: receivedAt)
        } catch {
            _ = try? storeUnparsed(
                text: text,
                sender: sender,
                receivedAt: receivedAt,
                reason: error.localizedDescription
            )
            throw error
        }

        guard case .parsed(let message) = outcome else {
            let stored = try storeUnparsed(
                text: text,
                sender: sender,
                receivedAt: receivedAt,
                reason: "Could not read this message."
            )
            return IngestOutcome(
                status: .unrecognised,
                entryID: nil,
                unparsedID: stored.id,
                summary: "Could not read this message. It is waiting in the Inbox."
            )
        }

        let hash = IngestService.dedupeHash(sender: sender, text: text)

        if let existing = try existingEntry(hash: hash) {
            return IngestOutcome(
                status: .duplicate,
                entryID: existing.id,
                summary: "Already recorded: \(message.payee.isEmpty ? message.ruleName : message.payee)."
            )
        }

        if message.role == .confirmation {
            return try ingestConfirmation(message, hash: hash, sender: sender, text: text)
        }

        let routed = routeAccount(for: message)
        // Never attach a message to an account in another currency: the minor units mean a
        // different amount. The row waits in review until the user picks a matching account.
        let account =
            routed.flatMap { candidate in
                message.currencyCode.isEmpty || candidate.currencyCode == message.currencyCode
                    ? candidate : nil
            }

        let effectiveSender = message.sender.isEmpty ? (sender ?? "") : message.sender

        // The reference identifies the movement. Match before creating anything so a
        // receipt waiting for its payment is upgraded instead of duplicated.
        let match = try MovementCorrelator(context: context).match(for: message)

        if case .entry(let existing) = match {
            if existing.isConfirmationOnly {
                return try upgrade(
                    existing,
                    with: message,
                    account: account,
                    hash: hash,
                    sender: effectiveSender
                )
            }

            return try absorb(existing, with: message, hash: hash, sender: effectiveSender)
        }

        // A message whose counterpart already belongs to a transfer is the other side of a
        // transfer the user created (or confirmed) earlier. Attach it to that leg instead of
        // creating a second one.
        if case .counterpart(let leg) = match, let transfer = leg.transfer {
            let opposite = leg.kind == .transferOut ? transfer.inTransaction : transfer.outTransaction

            if let opposite {
                return try absorbIntoExistingTransfer(
                    opposite,
                    with: message,
                    hash: hash,
                    sender: effectiveSender
                )
            }
        }

        var counterpartLeg: LedgerEntry?
        if case .counterpart(let leg) = match {
            guard !leg.isSoftDeleted, leg.status != .ignored else {
                return duplicateOutcome(leg, message: message)
            }

            counterpartLeg = leg
        }

        // The same bank reference on the same account is the same money, even when the
        // wording around it changed enough to defeat the text hash. This stays as a
        // fallback for references outside the correlation window.
        if let existing = try existingEntry(account: account, externalRef: message.reference),
            MovementRules.amountsAgree(
                minor: message.amountMinor,
                feeMinor: message.feeMinor,
                otherMinor: existing.amountMinor,
                otherFeeMinor: existing.feeMinor
            )
        {
            return IngestOutcome(
                status: .duplicate,
                entryID: existing.id,
                summary: "Already recorded: \(message.payee.isEmpty ? message.ruleName : message.payee)."
            )
        }
        let fingerprint = TemplateFingerprint.make(sender: effectiveSender, text: text)

        // A shape the user has already told us is not a transaction never needs Review.
        let suppression = try suppressionMemory(fingerprint: fingerprint)

        let categoriser = CategoriserService(context: context)
        let suggestions =
            suppression == nil
            ? (try? categoriser.suggest(
                payee: message.payee,
                amountMinor: message.amountMinor + message.feeMinor,
                date: message.occurredAt,
                account: account,
                kind: message.messageType.categoryKind
            )) ?? []
            : []

        // Only a merchant the user has explicitly trusted auto-files. Everything else waits
        // in the Inbox, because the user asked to categorise messages later.
        let autoCategory = suggestions.first { $0.isAutoApplicable }?.category
        var status: LedgerEntryStatus =
            suppression != nil
            ? .ignored
            : (account == nil || message.confidence < 0.85 || autoCategory == nil
                ? .needsReview
                : .confirmed)

        let entry = LedgerEntry(
            kind: message.messageType,
            amountMinor: message.amountMinor,
            feeMinor: message.feeMinor,
            currencyCode: message.currencyCode,
            occurredAt: message.occurredAt,
            payee: message.payee,
            note: "",
            source: .message
        )
        entry.account = account
        entry.externalRef = message.reference
        entry.counterpartRef = message.counterpartReference
        entry.ingestPayee = message.payee
        entry.rawMessage = keepsRawMessages() ? message.rawText : ""
        entry.messageSender = effectiveSender
        entry.ingestFingerprint = fingerprint
        entry.balanceAfterMinor = message.balanceAfterMinor
        entry.confidence = message.confidence
        entry.dedupeHash = hash
        entry.status = status

        if suppression == nil, message.messageType == .transferOut {
            entry.status = .needsReview
            status = .needsReview
        }

        if let suppression {
            suppression.hitCount += 1
            suppression.lastSeenAt = Date()
        }

        context.insert(entry)

        if message.messageType == .expense || message.messageType == .income {
            let line = LedgerEntryLine(
                amountMinor: message.amountMinor,
                category: suppression == nil ? autoCategory : nil
            )
            context.insert(line)
            line.entry = entry
            entry.lines = [line]
        }

        try context.save()

        if message.messageType.isTransferLeg {
            _ = try reconcileTransfer(
                entry: entry,
                message: message,
                counterpart: counterpartLeg
            )
        }

        ManotiNotifications.postDataChanged()

        let finalStatus = entry.status
        let amount = Money(
            minorUnits: message.amountMinor, currency: CurrencyCatalog.currency(for: message.currencyCode))
        let label = message.payee.isEmpty ? message.ruleName : message.payee
        let summary: String
        switch finalStatus {
            case .ignored:
                summary = "Auto-ignored: \(label)."
            case .confirmed:
                summary = "Recorded: \(amount.formatted()) \(label)"
            default:
                summary = "Needs review: \(amount.formatted()) \(label)"
        }

        return IngestOutcome(
            status: finalStatus == .confirmed
                ? .recorded : (finalStatus == .ignored ? .ignored : .needsReview),
            entryID: entry.id,
            summary: summary
        )
    }

    // MARK: - Correlation

    /// A receipt for a movement. It never creates a second row when the movement exists.
    private func ingestConfirmation(
        _ message: ParsedMessage,
        hash: String,
        sender: String?,
        text: String
    ) throws -> IngestOutcome {
        let effectiveSender = message.sender.isEmpty ? (sender ?? "") : message.sender

        if let existing = try existingConfirmation(reference: message.reference, sender: effectiveSender) {
            return duplicateOutcome(existing, message: message)
        }

        if let match = try MovementCorrelator(context: context).match(for: message),
            case .entry(let existing) = match
        {
            guard !existing.isSoftDeleted, existing.status != .ignored else {
                return duplicateOutcome(existing, message: message)
            }

            try enrich(existing, with: message, sender: effectiveSender)
            try context.save()
            ManotiNotifications.postDataChanged()

            let label = existing.payee.isEmpty ? message.payee : existing.payee
            return IngestOutcome(
                status: .duplicate,
                entryID: existing.id,
                summary: "Linked to \(label)."
            )
        }

        // The receipt arrived first. Record it as a reviewable expense so the payment is
        // never lost, and let the transaction upgrade it when it arrives.
        let entry = LedgerEntry(
            kind: message.messageType == .income ? .income : .expense,
            amountMinor: message.amountMinor,
            feeMinor: 0,
            currencyCode: message.currencyCode,
            occurredAt: message.occurredAt,
            payee: message.payee,
            note: "",
            source: .message
        )
        entry.ingestPayee = message.payee
        entry.confirmationRef = message.reference
        entry.confirmationSender = effectiveSender
        entry.confirmedAt = message.occurredAt
        entry.confirmationText = keepsRawMessages() ? text : ""
        entry.isConfirmationOnly = true
        entry.messageSender = effectiveSender
        entry.dedupeHash = hash
        entry.confidence = message.confidence
        entry.status = .needsReview
        context.insert(entry)

        if entry.kind == .expense || entry.kind == .income {
            let line = LedgerEntryLine(amountMinor: message.amountMinor)
            context.insert(line)
            line.entry = entry
            entry.lines = [line]
        }

        try context.save()
        ManotiNotifications.postDataChanged()

        let amount = Money(
            minorUnits: message.amountMinor,
            currency: CurrencyCatalog.currency(for: message.currencyCode)
        )
        let label = message.payee.isEmpty ? message.ruleName : message.payee
        return IngestOutcome(
            status: .needsReview,
            entryID: entry.id,
            summary: "Needs review: \(amount.formatted()) \(label) (bank receipt)."
        )
    }

    /// Adds what a receipt knows without touching what the user chose.
    private func enrich(_ entry: LedgerEntry, with message: ParsedMessage, sender: String) throws {
        guard !entry.isSoftDeleted, entry.status != .ignored else {
            return
        }

        if entry.channelName.isEmpty {
            let biller = entry.ingestPayee.isEmpty ? entry.payee : entry.ingestPayee
            if !biller.isEmpty {
                entry.channelName = biller
            }
        }

        if entry.payeeIsUnedited, !message.payee.isEmpty {
            entry.payee = message.payee
        }

        if entry.feeMinor == 0 {
            entry.feeMinor = message.feeMinor
        }

        if entry.balanceAfterMinor == nil {
            entry.balanceAfterMinor = message.balanceAfterMinor
        }

        if entry.externalRef.isEmpty {
            entry.externalRef = message.reference
        }

        if entry.counterpartRef.isEmpty {
            entry.counterpartRef = message.counterpartReference
        }

        if entry.confirmationRef.isEmpty {
            entry.confirmationRef = message.reference
        }

        entry.confirmationSender = sender

        if entry.confirmedAt == nil {
            entry.confirmedAt = message.occurredAt
        }

        if entry.confirmationText.isEmpty, keepsRawMessages() {
            entry.confirmationText = message.rawText
        }
    }

    /// A transaction matching a receipt-first entry. The merchant payee is kept.
    private func upgrade(
        _ entry: LedgerEntry,
        with message: ParsedMessage,
        account: Account?,
        hash: String,
        sender: String
    ) throws -> IngestOutcome {
        guard !entry.isSoftDeleted, entry.status != .ignored else {
            return duplicateOutcome(entry, message: message)
        }

        if entry.status == .needsReview {
            if entry.account == nil, let account {
                entry.account = account
            }

            entry.occurredAt = message.occurredAt
        }

        if entry.feeMinor == 0 {
            entry.feeMinor = message.feeMinor
        }

        if entry.balanceAfterMinor == nil {
            entry.balanceAfterMinor = message.balanceAfterMinor
        }

        if entry.externalRef.isEmpty {
            entry.externalRef = message.reference
        }

        if entry.counterpartRef.isEmpty {
            entry.counterpartRef = message.counterpartReference
        }

        if entry.channelName.isEmpty, !message.payee.isEmpty {
            entry.channelName = message.payee
        }

        // The transaction's payee is the biller, not the merchant. Recording it as the
        // ingested payee keeps `payeeIsUnedited` false, so a later receipt cannot replace
        // the merchant name.
        entry.ingestPayee = message.payee
        entry.dedupeHash = hash

        if entry.messageSender.isEmpty {
            entry.messageSender = sender
        }

        if entry.rawMessage.isEmpty, keepsRawMessages() {
            entry.rawMessage = message.rawText
        }

        entry.isConfirmationOnly = false

        try context.save()
        ManotiNotifications.postDataChanged()

        let amount = Money(minorUnits: entry.amountMinor, currency: entry.currency)
        let label = entry.payee.isEmpty ? message.ruleName : entry.payee
        return IngestOutcome(
            status: entry.status == .confirmed ? .recorded : .needsReview,
            entryID: entry.id,
            summary: entry.status == .confirmed
                ? "Recorded: \(amount.formatted()) \(label)"
                : "Needs review: \(amount.formatted()) \(label)"
        )
    }

    /// A second message for an entry that is already complete. Fill only gaps.
    private func absorb(
        _ entry: LedgerEntry,
        with message: ParsedMessage,
        hash: String,
        sender: String
    ) throws -> IngestOutcome {
        guard !entry.isSoftDeleted, entry.status != .ignored else {
            return duplicateOutcome(entry, message: message)
        }

        if entry.feeMinor == 0 {
            entry.feeMinor = message.feeMinor
        }

        if entry.balanceAfterMinor == nil {
            entry.balanceAfterMinor = message.balanceAfterMinor
        }

        if entry.externalRef.isEmpty {
            entry.externalRef = message.reference
        }

        if entry.counterpartRef.isEmpty {
            entry.counterpartRef = message.counterpartReference
        }

        if entry.dedupeHash.isEmpty {
            entry.dedupeHash = hash
        }

        if entry.rawMessage.isEmpty, keepsRawMessages() {
            entry.rawMessage = message.rawText
        }

        if entry.messageSender.isEmpty {
            entry.messageSender = sender
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        return duplicateOutcome(entry, message: message)
    }

    /// The other side of a transfer that already exists. Fill its references and evidence;
    /// never change its amount, account or date.
    private func absorbIntoExistingTransfer(
        _ entry: LedgerEntry,
        with message: ParsedMessage,
        hash: String,
        sender: String
    ) throws -> IngestOutcome {
        guard !entry.isSoftDeleted, entry.status != .ignored else {
            return duplicateOutcome(entry, message: message)
        }

        if entry.externalRef.isEmpty {
            entry.externalRef = message.reference
        }

        if entry.counterpartRef.isEmpty {
            entry.counterpartRef = message.counterpartReference
        }

        if entry.dedupeHash.isEmpty {
            entry.dedupeHash = hash
        }

        if entry.rawMessage.isEmpty, keepsRawMessages() {
            entry.rawMessage = message.rawText
        }

        if entry.messageSender.isEmpty {
            entry.messageSender = sender
        }

        if entry.balanceAfterMinor == nil {
            entry.balanceAfterMinor = message.balanceAfterMinor
        }

        if entry.payee.isEmpty, !message.payee.isEmpty {
            entry.payee = message.payee
        }

        if entry.kind == .transferOut, entry.feeMinor == 0 {
            entry.feeMinor = message.feeMinor
        }

        entry.status = .confirmed
        try context.save()
        ManotiNotifications.postDataChanged()

        return IngestOutcome(
            status: .duplicate,
            entryID: entry.id,
            summary: "Already part of a transfer."
        )
    }

    private func duplicateOutcome(_ entry: LedgerEntry, message: ParsedMessage) -> IngestOutcome {
        let label =
            entry.payee.isEmpty
            ? (message.payee.isEmpty ? message.ruleName : message.payee)
            : entry.payee
        return IngestOutcome(
            status: .duplicate,
            entryID: entry.id,
            summary: "Already recorded: \(label)."
        )
    }

    /// Links a transfer leg to its opposite, or builds the M-PESA leg when the bank message
    /// names a wallet the user owns.
    private func reconcileTransfer(
        entry: LedgerEntry,
        message: ParsedMessage,
        counterpart: LedgerEntry?
    ) throws -> Bool {
        guard entry.kind.isTransferLeg else {
            return false
        }

        if let counterpart {
            return try link(entry, with: counterpart)
        }

        guard entry.kind == .transferOut,
            entry.transfer == nil,
            let from = entry.account,
            !message.accountHint.isEmpty,
            !message.counterpartReference.isEmpty,
            let to = accountService.account(forIdentifier: message.accountHint),
            to.id != from.id,
            to.kind == .mobileMoney,
            to.currencyCode == entry.currencyCode
        else {
            return false
        }

        let inLeg = LedgerEntry(
            kind: .transferIn,
            amountMinor: entry.amountMinor,
            currencyCode: entry.currencyCode,
            occurredAt: entry.occurredAt,
            note: "",
            source: .message
        )
        inLeg.account = to
        inLeg.externalRef = message.counterpartReference
        inLeg.counterpartRef = message.reference
        context.insert(inLeg)

        let linked = try link(entry, with: inLeg)
        if !linked {
            context.delete(inLeg)
        }

        return linked
    }

    private func link(_ entry: LedgerEntry, with other: LedgerEntry) throws -> Bool {
        let outLeg = entry.kind == .transferOut ? entry : other
        let inLeg = entry.kind == .transferIn ? entry : other

        guard outLeg.kind == .transferOut,
            inLeg.kind == .transferIn,
            outLeg.transfer == nil,
            inLeg.transfer == nil,
            !outLeg.isSoftDeleted,
            !inLeg.isSoftDeleted,
            outLeg.status != .ignored,
            inLeg.status != .ignored,
            let from = outLeg.account,
            let to = inLeg.account,
            from.id != to.id
        else {
            return false
        }

        let previousOut = outLeg.status
        let previousIn = inLeg.status
        outLeg.status = .confirmed
        inLeg.status = .confirmed

        do {
            _ = try TransferLinker(context: context).link(outLeg: outLeg, inLeg: inLeg)
            return true
        } catch {
            outLeg.status = previousOut
            inLeg.status = previousIn
            return false
        }
    }

    /// Stable identity for a raw message, so a repeated automation never double-books it.
    public static func dedupeHash(sender: String?, text: String) -> String {
        let normalisedSender = sender.map(ParserService.normaliseForHash) ?? ""
        let normalised = "\(normalisedSender)|\(ParserService.normaliseForHash(text))"
        let digest = SHA256.hash(data: Data(normalised.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func storeUnparsed(
        text: String,
        sender: String?,
        receivedAt: Date,
        reason: String
    ) throws -> UnparsedMessage {
        let hash = IngestService.dedupeHash(sender: sender, text: text)

        var descriptor = FetchDescriptor<UnparsedMessage>(
            predicate: #Predicate<UnparsedMessage> { $0.dedupeHash == hash }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let message = UnparsedMessage(
            rawText: keepsRawMessages() ? text : "",
            sender: sender ?? "",
            receivedAt: receivedAt,
            reason: reason,
            dedupeHash: hash
        )
        context.insert(message)
        try context.save()
        ManotiNotifications.postDataChanged()
        return message
    }

    private func existingEntry(hash: String) throws -> LedgerEntry? {
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> { $0.dedupeHash == hash }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingConfirmation(reference: String, sender: String) throws -> LedgerEntry? {
        guard !reference.isEmpty else {
            return nil
        }

        let ref = reference
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> { $0.confirmationRef == ref }
        )
        descriptor.fetchLimit = 20
        return try context.fetch(descriptor).first {
            sender.isEmpty || $0.confirmationSender == sender
        }
    }

    private func existingEntry(account: Account?, externalRef: String) throws -> LedgerEntry? {
        guard let account, !externalRef.isEmpty else {
            return nil
        }

        let reference = externalRef
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> { $0.externalRef == reference && !$0.isSoftDeleted }
        )
        descriptor.fetchLimit = 20
        return try context.fetch(descriptor).first { $0.account?.id == account.id }
    }

    private func suppressionMemory(fingerprint: String) throws -> IngestMemory? {
        guard !fingerprint.isEmpty else {
            return nil
        }

        let suppressed = IngestMemoryReason.notATransaction.rawValue
        var descriptor = FetchDescriptor<IngestMemory>(
            predicate: #Predicate<IngestMemory> {
                $0.reasonRaw == suppressed && $0.fingerprint == fingerprint
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// A missing settings row uses the model default, which is to keep the text.
    private func keepsRawMessages() -> Bool {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first?.keepRawMessages) ?? true
    }

    private func routeAccount(for message: ParsedMessage) -> Account? {
        let senderAccount = accountService.account(forSender: message.sender)

        switch message.messageType {
            case .transferOut:
                // The `account` capture in a transfer-out message is the destination, so it
                // must never choose the account the money left.
                if let senderAccount {
                    return senderAccount
                }

                if !message.cardLast4.isEmpty,
                    let account = accountService.account(forIdentifier: message.cardLast4)
                {
                    return account
                }

            case .expense:
                if !message.cardLast4.isEmpty,
                    let account = accountService.account(forIdentifier: message.cardLast4)
                {
                    return account
                }

                if !message.accountHint.isEmpty,
                    let account = accountService.account(forIdentifier: message.accountHint)
                {
                    return account
                }

                if let senderAccount {
                    return senderAccount
                }

            default:
                if !message.accountHint.isEmpty,
                    let account = accountService.account(forIdentifier: message.accountHint)
                {
                    return account
                }

                if !message.cardLast4.isEmpty,
                    let account = accountService.account(forIdentifier: message.cardLast4)
                {
                    return account
                }

                if let senderAccount {
                    return senderAccount
                }
        }

        // A single account can receive a message that carries no ownership hint. A hint that
        // was present but unmatched is never overridden; the message waits in review.
        let hasOwnershipHint =
            !message.cardLast4.isEmpty
            || (message.messageType != .transferOut && !message.accountHint.isEmpty)
        guard !hasOwnershipHint else {
            return nil
        }

        let accounts = (try? accountService.fetchAccounts()) ?? []
        return accounts.count == 1 ? accounts.first : nil
    }
}
