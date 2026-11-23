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

    /// Messages the parser could not read. They are shown separately and never posted.
    public func unparsed() throws -> [UnparsedMessage] {
        try context.fetch(
            FetchDescriptor<UnparsedMessage>(
                sortBy: [SortDescriptor(\UnparsedMessage.receivedAt, order: .reverse)]
            )
        )
    }

    public func dismiss(_ message: UnparsedMessage) throws {
        context.delete(message)
        try context.save()
        ManotiNotifications.postDataChanged()
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

            if let category, !entry.payee.isEmpty {
                try categoriser.recordLearning(payee: entry.payee, category: category, account: account)
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        ManotiNotifications.postDataChanged()
    }

    public func ignore(_ entry: LedgerEntry) throws {
        guard !entry.isSoftDeleted else {
            throw InboxError.deletedEntry
        }

        guard entry.transfer == nil else {
            throw InboxError.linkedTransfer
        }

        entry.status = .ignored
        try context.save()
        ManotiNotifications.postDataChanged()
    }
}
