//
//  ReconciliationService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import CryptoKit
import Foundation
import Observation
import SwiftData

nonisolated public enum ReconcileError: Error, Equatable, Sendable {
    case invalidPeriod
    case sessionFinalised
    case unrecognisedMessage
    case transferNeedsPairing
}

extension ReconcileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .invalidPeriod: return "The reconciliation period is invalid."
            case .sessionFinalised: return "This reconciliation run has already been finished."
            case .unrecognisedMessage: return "This message cannot be imported."
            case .transferNeedsPairing:
                return "Transfers are paired on the Transfers screen, not imported as one leg."
        }
    }
}

/// The counts shown once a session has been finalised.
nonisolated public struct ReconcileSummary: Equatable, Sendable {
    public let messageCount: Int
    public let matchedCount: Int
    public let messageOnlyCount: Int
    public let appOnlyCount: Int
    public let possibleCount: Int
    public let ignoredCount: Int
    public let missingTimeCount: Int
    public let displayText: String

    public init(
        messageCount: Int,
        matchedCount: Int,
        messageOnlyCount: Int,
        appOnlyCount: Int,
        possibleCount: Int,
        ignoredCount: Int,
        missingTimeCount: Int,
        displayText: String
    ) {
        self.messageCount = messageCount
        self.matchedCount = matchedCount
        self.messageOnlyCount = messageOnlyCount
        self.appOnlyCount = appOnlyCount
        self.possibleCount = possibleCount
        self.ignoredCount = ignoredCount
        self.missingTimeCount = missingTimeCount
        self.displayText = displayText
    }
}

/// Collects messages for a period, matches them against the ledger, and keeps the
/// "in messages, not in app" and "in app, not in messages" buckets.
///
/// Matching never edits or deletes a ledger row: a message becomes an import only when the
/// user asks, and an app row is hidden only through the session's explicit ignore list.
@Observable
public final class ReconciliationService: Loggable {
    private let context: ModelContext
    private let calendar: Calendar
    private let accountService: AccountService

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
        self.accountService = AccountService(context: context)
    }

    // MARK: - Sessions

    /// Returns the open session for `token`, or the newest open session when `token` is nil.
    ///
    /// The period belongs to the first creation: a repeated Shortcut call with the same token
    /// keeps collecting into the same session instead of opening a second one.
    public func startSession(token: String?, periodStart: Date, periodEnd: Date) throws -> ReconcileSession {
        guard periodEnd > periodStart else {
            throw ReconcileError.invalidPeriod
        }

        if let token = normalisedToken(token) {
            if let existing = try openSession(token: token) {
                return existing
            }
        } else if let latest = try newestOpenSession() {
            return latest
        }

        let session = ReconcileSession(
            token: normalisedToken(token) ?? UUID().uuidString,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
        context.insert(session)
        try context.save()
        ManotiNotifications.postDataChanged()
        log("Started reconciliation session", level: .info)
        return session
    }

    public func latestSession() throws -> ReconcileSession? {
        var descriptor = FetchDescriptor<ReconcileSession>(
            sortBy: [SortDescriptor(\ReconcileSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The newest session for a token, finalised or not, or the newest session overall.
    public func session(token: String?) throws -> ReconcileSession? {
        guard let token = normalisedToken(token) else {
            return try latestSession()
        }

        var descriptor = FetchDescriptor<ReconcileSession>(
            predicate: #Predicate { $0.token == token },
            sortBy: [SortDescriptor(\ReconcileSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// How long a batch may keep adding messages to one run. A later run with the same
    /// constant token starts fresh instead of folding days together.
    private static let sessionReuseWindow: TimeInterval = 15 * 60

    private func openSession(token: String) throws -> ReconcileSession? {
        let descriptor = FetchDescriptor<ReconcileSession>(
            predicate: #Predicate { !$0.isFinalised && $0.token == token },
            sortBy: [SortDescriptor(\ReconcileSession.startedAt, order: .reverse)]
        )

        guard let session = try context.fetch(descriptor).first else {
            return nil
        }

        return Date().timeIntervalSince(session.startedAt) <= Self.sessionReuseWindow ? session : nil
    }

    private func newestOpenSession() throws -> ReconcileSession? {
        let descriptor = FetchDescriptor<ReconcileSession>(
            predicate: #Predicate { !$0.isFinalised },
            sortBy: [SortDescriptor(\ReconcileSession.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    private func normalisedToken(_ token: String?) -> String? {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Collection

    /// Parses one message and appends it to the session. A duplicate within the session is
    /// returned as-is rather than stored twice.
    @discardableResult
    public func collect(
        text: String,
        sender: String?,
        receivedAt: Date?,
        token: String?,
        periodStart: Date,
        periodEnd: Date
    ) throws -> ReconcileMessage {
        let session = try startSession(token: token, periodStart: periodStart, periodEnd: periodEnd)
        let hash = ReconciliationService.dedupeHash(
            sender: sender,
            text: text,
            receivedAt: receivedAt,
            calendar: calendar
        )

        if let existing = try existingMessage(hash: hash, in: session) {
            return existing
        }

        let ruleSets = try context.fetch(
            FetchDescriptor<ParseRuleSet>(sortBy: [SortDescriptor(\ParseRuleSet.priority)])
        )
        let fallback = receivedAt ?? Date()
        let outcome = ParserService.parse(
            text: text,
            sender: sender,
            receivedAt: fallback,
            ruleSets: ruleSets
        )

        let message: ReconcileMessage

        switch outcome { case .parsed(let parsed):
            message = ReconcileMessage(
                text: text,
                sender: parsed.sender,
                receivedAt: receivedAt,
                parsedKind: parsed.messageType,
                amountMinor: parsed.amountMinor,
                currencyCode: parsed.currencyCode,
                feeMinor: parsed.feeMinor,
                payee: parsed.payee,
                reference: parsed.reference,
                accountHint: parsed.accountHint.isEmpty ? parsed.cardLast4 : parsed.accountHint,
                occurredAt: parsed.occurredAt,
                dateFromMessage: parsed.dateFromMessage,
                confidence: parsed.confidence,
                classification: .pending,
                dedupeHash: hash
            )

            case .unrecognised:
                // Keep the raw text so the summary can count it and the user can inspect it.
                message = ReconcileMessage(
                    text: text,
                    sender: sender ?? "",
                    receivedAt: receivedAt,
                    parsedKind: nil,
                    amountMinor: 0,
                    currencyCode: CurrencyCatalog.defaultCurrency.code,
                    feeMinor: 0,
                    occurredAt: nil,
                    dateFromMessage: false,
                    confidence: 0,
                    classification: .pending,
                    dedupeHash: hash
                )
        }

        // A 24-hour Shortcut run can cross midnight, and the message body may carry an
        // earlier date than the received time. Widen the session so both days are compared.
        if let receivedAt {
            expandPeriod(of: session, toInclude: receivedAt)
        }

        if let occurredAt = message.occurredAt {
            expandPeriod(of: session, toInclude: occurredAt)
        }

        message.session = session
        context.insert(message)
        session.messageCount = try messageCount(in: session)
        try context.save()
        ManotiNotifications.postDataChanged()
        return message
    }

    /// Expands a session's half-open period to cover the whole calendar day of `date`.
    private func expandPeriod(of session: ReconcileSession, toInclude date: Date) {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return
        }

        if dayStart < session.periodStart {
            session.periodStart = dayStart
        }

        if dayEnd > session.periodEnd {
            session.periodEnd = dayEnd
        }
    }

    private func existingMessage(hash: String, in session: ReconcileSession) throws -> ReconcileMessage? {
        let sessionID = session.id
        let descriptor = FetchDescriptor<ReconcileMessage>(
            predicate: #Predicate { $0.session?.id == sessionID && $0.dedupeHash == hash }
        )
        return try context.fetch(descriptor).first
    }

    private func messageCount(in session: ReconcileSession) throws -> Int {
        let sessionID = session.id
        return try context.fetchCount(
            FetchDescriptor<ReconcileMessage>(predicate: #Predicate { $0.session?.id == sessionID })
        )
    }

    /// Stable identity for a collected message: sender, normalised text and the day it
    /// arrived. Messages without a received time still dedupe within the session.
    public static func dedupeHash(
        sender: String?,
        text: String,
        receivedAt: Date?,
        calendar: Calendar
    ) -> String {
        let day: String
        if let receivedAt {
            day = String(Int(calendar.startOfDay(for: receivedAt).timeIntervalSince1970))
        } else {
            day = "no-date"
        }

        let payload =
            "\(sender?.uppercased() ?? "")|\(ParserService.normaliseForHash(text))|\(day)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Finalise

    /// Matches every collected message against posted ledger rows in the session period.
    ///
    /// Order is deterministic, entries are used at most once, and nothing is edited or
    /// deleted. Weak same-day matches are `.possible` and stay out of the matched count.
    @discardableResult
    public func finalise(_ session: ReconcileSession) throws -> ReconcileSummary {
        guard !session.isFinalised else {
            throw ReconcileError.sessionFinalised
        }

        guard session.periodEnd > session.periodStart else {
            throw ReconcileError.invalidPeriod
        }

        let messages = try messages(in: session)
        for message in messages {
            message.classification = .pending
            message.matchedEntryID = nil
        }

        let entries = try postedEntries(in: session)
        var usedEntryIDs: Set<UUID> = []
        var accountCache: [String: Account?] = [:]

        for message in ordered(messages) {
            let messageAccount = account(
                for: message,
                cache: &accountCache
            )

            if let match = match(
                message: message,
                messageAccount: messageAccount,
                entries: entries,
                usedEntryIDs: usedEntryIDs
            ) {
                message.classification = match.classification
                if match.classification == .matched {
                    message.matchedEntryID = match.entry.id
                    usedEntryIDs.insert(match.entry.id)
                }
            } else {
                message.classification = .missing
            }
        }

        let matchedCount = messages.filter { $0.classification == .matched }.count
        let messageOnlyCount = messages.filter { $0.classification == .missing }.count
        let appOnlyCount = try appOnlyEntries(in: session).count

        session.messageCount = messages.count
        session.matchedCount = matchedCount
        session.messageOnlyCount = messageOnlyCount
        session.appOnlyCount = appOnlyCount
        session.isFinalised = true
        session.completedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()

        let summary = try summary(for: session)

        log("Finalised reconciliation: \(summary.displayText)", level: .info)
        return summary
    }

    /// The session's counts, finalising first when the session is still open.
    ///
    /// Repeated calls on a finalised session are safe: Shortcut reruns show the same summary
    /// instead of failing on an already-closed session.
    public func summary(for session: ReconcileSession) throws -> ReconcileSummary {
        if !session.isFinalised {
            return try finalise(session)
        }

        let messages = try messages(in: session)
        // Derive the counts on every read: an import or ignore changes the buckets after the
        // session was finalised, and stored totals would then disagree with the lists.
        let matchedCount = messages.filter { $0.classification == .matched }.count
        let messageOnlyCount = messages.filter { $0.classification == .missing }.count
        let possibleCount = messages.filter { $0.classification == .possible }.count
        let missingTimeCount = messages.filter { $0.receivedAt == nil }.count
        let ignoredCount = session.ignoredEntryIDs.count
        let appOnlyCount = try appOnlyEntries(in: session).count

        return ReconcileSummary(
            messageCount: messages.count,
            matchedCount: matchedCount,
            messageOnlyCount: messageOnlyCount,
            appOnlyCount: appOnlyCount,
            possibleCount: possibleCount,
            ignoredCount: ignoredCount,
            missingTimeCount: missingTimeCount,
            displayText: ReconciliationService.displayText(
                messageCount: messages.count,
                matchedCount: matchedCount,
                messageOnlyCount: messageOnlyCount,
                appOnlyCount: appOnlyCount,
                possibleCount: possibleCount,
                ignoredCount: ignoredCount,
                missingTimeCount: missingTimeCount
            )
        )
    }

    /// A single-message preview of how `finalise` would classify it, without changing the session.
    ///
    /// The Shortcut action returns this so it can build its own per-message text.
    public func classificationPreview(
        for message: ReconcileMessage,
        in session: ReconcileSession
    ) throws -> ReconcileClassification {
        guard message.parsedKind != nil else {
            return .missing
        }

        let entries = try postedEntries(in: session)
        let usedEntryIDs = Set((session.messages ?? []).compactMap(\.matchedEntryID))
        var accountCache: [String: Account?] = [:]
        let messageAccount = account(for: message, cache: &accountCache)

        guard
            let match = match(
                message: message,
                messageAccount: messageAccount,
                entries: entries,
                usedEntryIDs: usedEntryIDs
            )
        else {
            return .missing
        }

        return match.classification
    }

    private struct ReconcileMatch {
        let entry: LedgerEntry
        let classification: ReconcileClassification
    }

    private func match(
        message: ReconcileMessage,
        messageAccount: Account?,
        entries: [LedgerEntry],
        usedEntryIDs: Set<UUID>
    ) -> ReconcileMatch? {
        guard let kind = message.parsedKind else {
            return nil
        }

        let candidates = entries.filter { entry in
            !usedEntryIDs.contains(entry.id) && entry.kind == kind
        }

        // 1. An exact reference is the strongest signal.
        if let reference = nonEmpty(message.reference) {
            let referenceMatches =
                candidates
                .filter { $0.externalRef == reference }
                .filter { accountsDoNotConflict(messageAccount, $0.account) }
                .sorted(by: entryOrder)

            if let entry = referenceMatches.first {
                return ReconcileMatch(entry: entry, classification: .matched)
            }
        }

        // Without a received time every remaining rule would be guessing.
        guard let receivedAt = message.receivedAt else {
            return nil
        }

        // 2. Same known account, amount within 1%, and within ten minutes.
        let timedMatches =
            candidates
            .filter { sameKnownAccount(messageAccount, $0.account) }
            .filter { $0.currencyCode == message.currencyCode }
            .filter {
                amountMatches(message: message, entry: $0, tolerance: 0.01)
                    && abs($0.occurredAt.timeIntervalSince(receivedAt)) <= 10 * 60
            }
            .sorted { lhs, rhs in
                let left = abs(lhs.occurredAt.timeIntervalSince(receivedAt))
                let right = abs(rhs.occurredAt.timeIntervalSince(receivedAt))
                return left == right ? entryOrder(lhs, rhs) : left < right
            }

        if let entry = timedMatches.first {
            return ReconcileMatch(entry: entry, classification: .matched)
        }

        // 3. Exact amount on the same account and calendar day is only a weak match.
        let possibleMatches =
            candidates
            .filter { sameKnownAccount(messageAccount, $0.account) }
            .filter { $0.currencyCode == message.currencyCode }
            .filter {
                amountMatches(message: message, entry: $0, tolerance: nil)
                    && calendar.isDate($0.occurredAt, inSameDayAs: receivedAt)
            }
            .sorted(by: entryOrder)

        if let entry = possibleMatches.first {
            return ReconcileMatch(entry: entry, classification: .possible)
        }

        return nil
    }

    private func amountMatches(message: ReconcileMessage, entry: LedgerEntry, tolerance: Double?) -> Bool {
        let messageAmount = message.totalAmountMinor
        guard messageAmount > 0 else {
            return false
        }

        let entryAmount = abs(entry.signedAmountMinor)

        guard let tolerance else {
            return messageAmount == entryAmount
        }

        let difference = abs(Double(messageAmount - entryAmount))
        return difference <= Double(entryAmount) * tolerance
    }

    private func sameKnownAccount(_ messageAccount: Account?, _ entryAccount: Account?) -> Bool {
        guard let messageAccount, let entryAccount else {
            return false
        }

        return messageAccount.id == entryAccount.id
    }

    /// A reference match may cross an unknown account, but never two known different ones.
    private func accountsDoNotConflict(_ messageAccount: Account?, _ entryAccount: Account?) -> Bool {
        guard let messageAccount, let entryAccount else {
            return true
        }

        return messageAccount.id == entryAccount.id
    }

    private func entryOrder(_ lhs: LedgerEntry, _ rhs: LedgerEntry) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func account(for message: ReconcileMessage, cache: inout [String: Account?]) -> Account? {
        let hint = message.accountHint
        guard !hint.isEmpty else {
            return nil
        }

        if let cached = cache[hint] {
            return cached
        }

        let resolved = accountService.account(forIdentifier: hint)
        cache[hint] = resolved
        return resolved
    }

    /// Messages in the session, ordered for display. Screens read through the service so
    /// they never need the SwiftData environment context.
    public func messages(in session: ReconcileSession) throws -> [ReconcileMessage] {
        let sessionID = session.id
        return ordered(
            try context.fetch(
                FetchDescriptor<ReconcileMessage>(predicate: #Predicate { $0.session?.id == sessionID })
            )
        )
    }

    /// Messages sorted by the time they are known to have happened, then by id.
    private func ordered(_ messages: [ReconcileMessage]) -> [ReconcileMessage] {
        messages.sorted { lhs, rhs in
            let left = lhs.receivedAt ?? lhs.occurredAt ?? lhs.createdAt
            let right = rhs.receivedAt ?? rhs.occurredAt ?? rhs.createdAt

            if left != right {
                return left < right
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func postedEntries(in session: ReconcileSession) throws -> [LedgerEntry] {
        let start = session.periodStart
        let end = session.periodEnd
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate {
                !$0.isSoftDeleted && $0.statusRaw != "ignored"
                    && $0.occurredAt >= start && $0.occurredAt < end
            }
        )

        return try context.fetch(descriptor).filter { $0.kind != .openingBalance }
    }

    // MARK: - App-only bucket

    /// Posted ledger rows in the period that no message matched and the user has not ignored.
    public func appOnlyEntries(in session: ReconcileSession) throws -> [LedgerEntry] {
        let ignored = session.ignoredEntryIDs
        let matched = Set(
            (session.messages ?? []).compactMap(\.matchedEntryID)
        )

        return try postedEntries(in: session)
            .filter { !ignored.contains($0.id) && !matched.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt {
                    return lhs.occurredAt > rhs.occurredAt
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    // MARK: - Imports and ignores

    /// Creates one `needsReview` ledger row from a missing or possible message.
    ///
    /// The message's matched entry id doubles as the import marker, so a repeated tap returns
    /// the same row instead of importing again.
    @discardableResult
    public func importMessage(_ message: ReconcileMessage) throws -> LedgerEntry {
        if let entryID = message.matchedEntryID,
            let existing = try entry(withID: entryID)
        {
            return existing
        }

        guard message.classification == .missing || message.classification == .possible else {
            throw ReconcileError.unrecognisedMessage
        }

        guard let kind = message.parsedKind, message.amountMinor > 0 else {
            throw ReconcileError.unrecognisedMessage
        }

        guard kind != .transferOut, kind != .transferIn else {
            throw ReconcileError.transferNeedsPairing
        }

        // A possible duplicate already matches a real row. Importing it with an account
        // would count the same money twice, so it waits for the Inbox without an account.
        let account = message.classification == .possible ? nil : routedAccount(for: message)
        let occurredAt = message.occurredAt ?? message.receivedAt ?? Date()
        let entry = LedgerEntry(
            kind: kind,
            amountMinor: message.amountMinor,
            feeMinor: message.feeMinor,
            currencyCode: account?.currencyCode ?? message.currencyCode,
            occurredAt: occurredAt,
            payee: message.payee,
            note: "Imported from reconciliation",
            source: .reconcile
        )
        entry.account = account
        entry.status = .needsReview
        entry.externalRef = message.reference
        entry.rawMessage = message.text
        entry.messageSender = message.sender
        entry.confidence = message.confidence
        entry.dedupeHash = IngestService.dedupeHash(sender: message.sender, text: message.text)
        context.insert(entry)

        message.classification = .imported
        message.matchedEntryID = entry.id

        try context.save()
        ManotiNotifications.postDataChanged()
        log("Imported one reconciled message", level: .info)
        return entry
    }

    /// Adds an app row to the session's ignore list. Never deletes the row.
    public func ignore(appEntry: LedgerEntry, in session: ReconcileSession) throws {
        var ids = session.ignoredEntryIDs
        ids.insert(appEntry.id)
        session.storeIgnoredEntryIDs(ids)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func unignore(appEntry: LedgerEntry, in session: ReconcileSession) throws {
        var ids = session.ignoredEntryIDs
        ids.remove(appEntry.id)
        session.storeIgnoredEntryIDs(ids)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    private func routedAccount(for message: ReconcileMessage) -> Account? {
        let hint = message.accountHint
        guard !hint.isEmpty else {
            return nil
        }

        return accountService.account(forIdentifier: hint)
    }

    public func entry(withID id: UUID) throws -> LedgerEntry? {
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    // MARK: - Display

    public static func displayText(
        messageCount: Int,
        matchedCount: Int,
        messageOnlyCount: Int,
        appOnlyCount: Int,
        possibleCount: Int,
        ignoredCount: Int,
        missingTimeCount: Int
    ) -> String {
        var parts = [
            "\(messageCount) messages",
            "\(matchedCount) matched",
            "\(messageOnlyCount) missing from app",
            "\(appOnlyCount) not in messages",
        ]

        if possibleCount > 0 {
            parts.append("\(possibleCount) possible")
        }

        if ignoredCount > 0 {
            parts.append("\(ignoredCount) ignored")
        }

        if missingTimeCount > 0 {
            parts.append("\(missingTimeCount) without a date")
        }

        return parts.joined(separator: " · ")
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
