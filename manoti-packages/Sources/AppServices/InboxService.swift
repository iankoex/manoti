//
//  InboxService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum InboxError: Error, Equatable {
    case missingAccount
    case archivedAccount
    case archivedCategory
    case linkedTransfer
    case deletedEntry
    case currencyMismatch(expected: String, actual: String)
}

extension InboxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .missingAccount:
                return "Choose an account for this entry."
            case .archivedAccount:
                return "That account is archived. Choose an active account."
            case .archivedCategory:
                return "That category is archived. Choose an active category."
            case .linkedTransfer:
                return "This entry belongs to a transfer. Review it from the Transfers screen."
            case .deletedEntry:
                return "This entry has already been deleted."
            case .currencyMismatch(let expected, let actual):
                return "This message is in \(actual). Choose a \(actual) account, not \(expected)."
        }
    }
}

@Observable
public final class InboxService: Loggable {
    private let context: ModelContext
    private let categoriser: CategoriserService

    public init(context: ModelContext) {
        self.context = context
        self.categoriser = CategoriserService(context: context)
    }

    public func pending() throws -> [LedgerEntry] {
        try context.fetch(
            FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> {
                    !$0.isSoftDeleted && $0.statusRaw == "needsReview" && $0.transfer == nil
                },
                sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
            )
        )
    }

    /// Messages the parser could not read. Dismissed rows stay behind the scenes so the
    /// same shape is not new work next time.
    public func unparsed() throws -> [UnparsedMessage] {
        try context.fetch(
            FetchDescriptor<UnparsedMessage>(
                predicate: #Predicate<UnparsedMessage> { !$0.isDismissed },
                sortBy: [SortDescriptor(\UnparsedMessage.receivedAt, order: .reverse)]
            )
        )
    }

    public func dismiss(_ message: UnparsedMessage) throws {
        message.isDismissed = true
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// The account this merchant was last filed under, so Review can pre-fill it when
    /// routing did not identify one. Never crosses currencies or archived accounts.
    public func suggestedAccount(for entry: LedgerEntry) -> Account? {
        let key = MerchantKey.normalise(entry.payee)
        guard !key.isEmpty,
            let memories = try? context.fetch(FetchDescriptor<MerchantMemory>()),
            let account = memories.first(where: { $0.merchantKey == key })?.account,
            !account.isArchived,
            entry.currencyCode.isEmpty || account.currencyCode == entry.currencyCode
        else {
            return nil
        }

        return account
    }

    /// Whether this merchant has been explicitly trusted to file without review.
    public func autoApply(for payee: String) -> Bool {
        let key = MerchantKey.normalise(payee)
        guard !key.isEmpty,
            let memories = try? context.fetch(FetchDescriptor<MerchantMemory>())
        else {
            return false
        }

        return memories.first(where: { $0.merchantKey == key })?.autoApply ?? false
    }

    public func setAutoApply(_ enabled: Bool, for payee: String) throws {
        try categoriser.setAutoApply(enabled, for: payee)
    }

    public func suggestions(for entry: LedgerEntry) throws -> [CategorySuggestion] {
        let kind = entry.kind.categoryKind
        let suggestions = try categoriser.suggest(
            payee: entry.payee,
            amountMinor: entry.amountMinor + entry.feeMinor,
            date: entry.occurredAt,
            account: entry.account,
            kind: kind
        )

        guard suggestions.isEmpty, let fallback = try fallbackCategory(for: entry.kind) else {
            return suggestions
        }

        return [
            CategorySuggestion(
                category: fallback,
                confidence: 0.3,
                reason: entry.kind == .income ? "Income — choose the source" : "No match — pick a category"
            )
        ]
    }

    private func fallbackCategory(for kind: LedgerEntryKind) throws -> SpendingCategory? {
        let name = kind == .income ? "Other income" : "Uncategorised"
        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        return categories.first { $0.name == name && $0.kind == kind.categoryKind }
    }

    public func confirm(
        _ entry: LedgerEntry,
        account: Account?,
        category: SpendingCategory?
    ) throws {
        guard !entry.isSoftDeleted else {
            throw InboxError.deletedEntry
        }

        guard entry.transfer == nil else {
            throw InboxError.linkedTransfer
        }

        guard let account else {
            throw InboxError.missingAccount
        }

        guard !account.isArchived else {
            throw InboxError.archivedAccount
        }

        guard entry.currencyCode.isEmpty || entry.currencyCode == account.currencyCode else {
            throw InboxError.currencyMismatch(expected: account.currencyCode, actual: entry.currencyCode)
        }

        if let category, category.isArchived {
            throw InboxError.archivedCategory
        }

        do {
            entry.account = account
            entry.category = category
            entry.status = .confirmed

            // Merchant learning happens in `LedgerService.update`, which the review form
            // calls with the edited fields before this confirmation. Learning here would
            // count the same filing twice.
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        ManotiNotifications.postDataChanged()
    }

    public func ignore(_ entry: LedgerEntry, reason: IngestMemoryReason = .notATransaction) throws {
        guard !entry.isSoftDeleted else {
            throw InboxError.deletedEntry
        }

        guard entry.transfer == nil else {
            throw InboxError.linkedTransfer
        }

        entry.status = .ignored

        // Only a fingerprint computed at ingest can teach anything. When the fingerprint
        // is missing (an older row, or a manually created entry) the ignore still works,
        // it just has nothing durable to remember.
        if !entry.ingestFingerprint.isEmpty {
            try recordMemory(for: entry, reason: reason)
        }

        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// Rows ingest filed automatically because the user ignored that message shape before.
    public func autoIgnored() throws -> [LedgerEntry] {
        try context.fetch(
            FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> {
                    !$0.isSoftDeleted && $0.statusRaw == "ignored" && $0.sourceRaw == "message"
                },
                sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
            )
        )
    }

    /// Puts an auto-ignored row back in Review and forgets the pattern that hid it.
    public func undoAutoIgnore(_ entry: LedgerEntry) throws {
        entry.status = .needsReview

        if !entry.ingestFingerprint.isEmpty {
            let fingerprint = entry.ingestFingerprint
            let memories = try context.fetch(FetchDescriptor<IngestMemory>())
            for memory in memories
            where memory.fingerprint == fingerprint && memory.reason == .notATransaction {
                context.delete(memory)
            }
        }

        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// A likely repeat of money already in the ledger. Never linked automatically.
    public func possibleDuplicate(of entry: LedgerEntry) -> LedgerEntry? {
        guard let account = entry.account else {
            return nil
        }

        let kindRaw = entry.kindRaw
        let amountMinor = entry.amountMinor
        let window: TimeInterval = 5 * 60
        let lower = entry.occurredAt.addingTimeInterval(-window)
        let upper = entry.occurredAt.addingTimeInterval(window)

        let candidates = try? context.fetch(
            FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> {
                    !$0.isSoftDeleted && $0.statusRaw != "ignored"
                        && $0.kindRaw == kindRaw && $0.amountMinor == amountMinor
                }
            )
        )

        return (candidates ?? []).first {
            $0.id != entry.id
                && $0.account?.id == account.id
                && $0.occurredAt >= lower
                && $0.occurredAt <= upper
        }
    }

    /// Everything the app has learned from the Inbox, newest first.
    public func memories() throws -> [IngestMemory] {
        try context.fetch(
            FetchDescriptor<IngestMemory>(
                sortBy: [SortDescriptor(\IngestMemory.lastSeenAt, order: .reverse)]
            )
        )
    }

    public func deleteMemory(_ memory: IngestMemory) throws {
        context.delete(memory)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    private func recordMemory(for entry: LedgerEntry, reason: IngestMemoryReason) throws {
        let fingerprint = entry.ingestFingerprint
        let memories = try context.fetch(FetchDescriptor<IngestMemory>())
        let memory =
            memories.first { $0.fingerprint == fingerprint && $0.reason == reason }
            ?? {
                let created = IngestMemory(
                    sender: entry.messageSender,
                    fingerprint: fingerprint,
                    reason: reason
                )
                context.insert(created)
                return created
            }()

        memory.hitCount += 1
        memory.lastSeenAt = Date()
        memory.amountMinor = entry.amountMinor
        memory.kindRaw = entry.kindRaw
        memory.externalRef = entry.externalRef
    }
}
