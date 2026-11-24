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

        let routed = routeAccount(for: message)
        // Never attach a message to an account in another currency: the minor units mean a
        // different amount. The row waits in review until the user picks a matching account.
        let account =
            routed.flatMap { candidate in
                message.currencyCode.isEmpty || candidate.currencyCode == message.currencyCode
                    ? candidate : nil
            }

        // The same bank reference on the same account is the same money, even when the
        // wording around it changed enough to defeat the text hash.
        if let existing = try existingEntry(account: account, externalRef: message.reference) {
            return IngestOutcome(
                status: .duplicate,
                entryID: existing.id,
                summary: "Already recorded: \(message.payee.isEmpty ? message.ruleName : message.payee)."
            )
        }

        let effectiveSender = message.sender.isEmpty ? (sender ?? "") : message.sender
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
        entry.category = suppression == nil ? autoCategory : nil
        entry.externalRef = message.reference
        entry.counterpartRef = message.counterpartReference
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
        try context.save()
        ManotiNotifications.postDataChanged()

        let amount = Money(
            minorUnits: message.amountMinor, currency: CurrencyCatalog.currency(for: message.currencyCode))
        let label = message.payee.isEmpty ? message.ruleName : message.payee
        let summary: String
        switch status {
            case .ignored:
                summary = "Auto-ignored: \(label)."
            case .confirmed:
                summary = "Recorded: \(amount.formatted()) \(label)"
            default:
                summary = "Needs review: \(amount.formatted()) \(label)"
        }

        return IngestOutcome(
            status: status == .confirmed ? .recorded : (status == .ignored ? .ignored : .needsReview),
            entryID: entry.id,
            summary: summary
        )
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
