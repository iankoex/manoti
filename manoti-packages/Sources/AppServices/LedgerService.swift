//
//  LedgerService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum LedgerError: Error, Equatable {
    case nonPositiveAmount
    case missingAccount
    case archivedAccount
    case alreadyDeleted
    case linkedEntry
    case currencyMismatch(expected: String, actual: String)
}

extension LedgerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .nonPositiveAmount:
                return "Enter an amount greater than zero."
            case .missingAccount:
                return "Choose an account for this entry."
            case .archivedAccount:
                return "That account is archived. Choose an active account."
            case .alreadyDeleted:
                return "This entry has already been deleted."
            case .linkedEntry:
                return "This entry belongs to a transfer, loan or investment. Change it from its own screen."
            case .currencyMismatch(let expected, let actual):
                return "This entry is in \(actual). Choose an account in \(actual), not \(expected)."
        }
    }
}

@Observable
public final class LedgerService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func record(
        kind: LedgerEntryKind,
        amountMinor: Int64,
        feeMinor: Int64 = 0,
        account: Account?,
        category: SpendingCategory? = nil,
        payee: String = "",
        note: String = "",
        occurredAt: Date = Date(),
        source: LedgerEntrySource = .manual
    ) throws -> LedgerEntry {
        if kind == .adjustment || kind == .openingBalance {
            guard amountMinor != 0 else {
                throw LedgerError.nonPositiveAmount
            }
        } else {
            guard amountMinor > 0, feeMinor >= 0 else {
                throw LedgerError.nonPositiveAmount
            }
        }

        // Background ingest and reconciliation may store an unrouted entry for review;
        // a manual entry may not.
        if account == nil, source != .message, source != .reconcile {
            throw LedgerError.missingAccount
        }

        if let account, account.isArchived {
            throw LedgerError.archivedAccount
        }

        let currencyCode = account?.currencyCode ?? CurrencyCatalog.defaultCurrency.code
        let status: LedgerEntryStatus = account == nil ? .needsReview : .confirmed

        let entry = LedgerEntry(
            kind: kind,
            amountMinor: amountMinor,
            feeMinor: feeMinor,
            currencyCode: currencyCode,
            occurredAt: occurredAt,
            payee: payee.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source
        )
        entry.account = account
        entry.category = category
        entry.status = status

        context.insert(entry)
        try context.save()
        ManotiNotifications.postDataChanged()
        return entry
    }

    /// Applies a manual edit to an unlinked entry.
    ///
    /// Amount rules mirror `record`. Transfers, loans and investment cash flows keep their
    /// ledger legs in step through their own services, so editing one here is refused.
    /// The entry keeps its identity, source, raw message, external reference, dedupe hash,
    /// status and timestamps.
    @discardableResult
    public func update(
        _ entry: LedgerEntry,
        kind: LedgerEntryKind,
        amountMinor: Int64,
        feeMinor: Int64,
        account: Account?,
        category: SpendingCategory?,
        payee: String,
        note: String,
        occurredAt: Date
    ) throws -> LedgerEntry {
        guard !entry.isSoftDeleted else {
            throw LedgerError.alreadyDeleted
        }

        guard entry.transfer == nil, entry.loan == nil, entry.investmentCashFlow == nil else {
            throw LedgerError.linkedEntry
        }

        if kind == .adjustment || kind == .openingBalance {
            guard amountMinor != 0 else {
                throw LedgerError.nonPositiveAmount
            }
        } else {
            guard amountMinor > 0, feeMinor >= 0 else {
                throw LedgerError.nonPositiveAmount
            }
        }

        guard let account else {
            throw LedgerError.missingAccount
        }

        guard !account.isArchived else {
            throw LedgerError.archivedAccount
        }

        guard entry.currencyCode.isEmpty || entry.currencyCode == account.currencyCode else {
            throw LedgerError.currencyMismatch(expected: account.currencyCode, actual: entry.currencyCode)
        }

        let movedAnchor =
            entry.account?.id != account.id
            || entry.amountMinor != amountMinor
            || entry.feeMinor != feeMinor
            || entry.occurredAt != occurredAt
            || entry.currencyCode != account.currencyCode

        entry.kind = kind
        entry.amountMinor = amountMinor
        entry.feeMinor = feeMinor
        entry.account = account
        entry.currencyCode = account.currencyCode
        entry.category = category
        entry.payee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.occurredAt = occurredAt

        if movedAnchor {
            // The reported bank balance belongs to the old account, amount and date.
            entry.balanceAfterMinor = nil
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        return entry
    }

    public func delete(_ entry: LedgerEntry) throws {
        guard !entry.isSoftDeleted else {
            throw LedgerError.alreadyDeleted
        }

        guard entry.transfer == nil, entry.loan == nil, entry.investmentCashFlow == nil else {
            throw LedgerError.linkedEntry
        }

        entry.isSoftDeleted = true
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func undoDelete(_ entry: LedgerEntry) throws {
        entry.isSoftDeleted = false
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func recent(limit: Int = 20) throws -> [LedgerEntry] {
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.kindRaw != "openingBalance" && $0.statusRaw != "ignored"
            },
            sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func balance(for account: Account) -> Money {
        Money(minorUnits: AccountBalance.balanceMinor(for: account), currency: account.currency)
    }
}
