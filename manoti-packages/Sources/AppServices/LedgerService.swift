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
    case linesRequired
    case linesNotAllowed
    case lineAmountInvalid
    case linesDoNotMatchTotal(expectedMinor: Int64, actualMinor: Int64)
    case lineCategoryMismatch
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
            case .linesRequired:
                return "Add at least one line to this entry."
            case .linesNotAllowed:
                return "This kind of entry cannot be split."
            case .lineAmountInvalid:
                return "Every line needs an amount greater than zero."
            case .linesDoNotMatchTotal(let expectedMinor, let actualMinor):
                let currency = CurrencyCatalog.defaultCurrency
                let expected = Money(minorUnits: expectedMinor, currency: currency)
                let actual = Money(minorUnits: actualMinor, currency: currency)
                return "The lines add up to \(actual.formatted()), but the entry is \(expected.formatted())."
            case .lineCategoryMismatch:
                return "A line uses a category that does not match the entry's kind."
        }
    }
}

@Observable
public final class LedgerService: Loggable {
    private let context: ModelContext
    private let categoriser: CategoriserService

    public init(context: ModelContext) {
        self.context = context
        self.categoriser = CategoriserService(context: context)
    }

    @discardableResult
    public func record(
        kind: LedgerEntryKind,
        amountMinor: Int64,
        feeMinor: Int64 = 0,
        account: Account?,
        lines: [LedgerLineInput],
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

        try validate(lines: lines, kind: kind, amountMinor: amountMinor)

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
        entry.status = status

        context.insert(entry)
        replaceLines(on: entry, with: lines)

        // Only a person's own filing teaches the merchant. Ingest and reconciliation
        // create rows directly and are not evidence of a preference. A split teaches its
        // proportions, a single line teaches its category.
        if (source == .manual || source == .shortcut), !entry.payee.isEmpty {
            if let category = singleCategory(in: lines) {
                try categoriser.recordLearning(payee: entry.payee, category: category, account: account)
            } else if let template = SplitTemplate.from(lines: lines) {
                try categoriser.recordSplitLearning(
                    payee: entry.payee,
                    template: template,
                    account: account
                )
            }
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        return entry
    }

    /// Records a single-line entry. Multi-line callers use the `lines:` form.
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
        try record(
            kind: kind,
            amountMinor: amountMinor,
            feeMinor: feeMinor,
            account: account,
            lines: Self.singleLine(kind: kind, amountMinor: amountMinor, category: category),
            payee: payee,
            note: note,
            occurredAt: occurredAt,
            source: source
        )
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
        lines: [LedgerLineInput],
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

        try validate(lines: lines, kind: kind, amountMinor: amountMinor)

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
        let previousCategoryIDs = Set(entry.orderedLines.compactMap { $0.category?.id })
        let previousTemplate = SplitTemplate.from(
            lines: entry.orderedLines.map {
                LedgerLineInput(amountMinor: $0.amountMinor, category: $0.category)
            }
        )

        entry.kind = kind
        entry.amountMinor = amountMinor
        entry.feeMinor = feeMinor
        entry.account = account
        entry.currencyCode = account.currencyCode
        entry.payee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.occurredAt = occurredAt

        replaceLines(on: entry, with: lines)

        if movedAnchor {
            // The reported bank balance belongs to the old account, amount and date.
            entry.balanceAfterMinor = nil
        }

        // A correction is the strongest signal there is; an edit that leaves the
        // category alone must not inflate the count.
        if !entry.payee.isEmpty {
            if let category = singleCategory(in: lines), previousCategoryIDs != [category.id] {
                try categoriser.recordLearning(payee: entry.payee, category: category, account: account)
            } else if let template = SplitTemplate.from(lines: lines), template != previousTemplate {
                try categoriser.recordSplitLearning(
                    payee: entry.payee,
                    template: template,
                    account: account
                )
            }
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        return entry
    }

    /// Applies a single-line edit. Multi-line callers use the `lines:` form.
    @discardableResult
    public func update(
        _ entry: LedgerEntry,
        kind: LedgerEntryKind,
        amountMinor: Int64,
        feeMinor: Int64,
        account: Account?,
        category: SpendingCategory? = nil,
        payee: String,
        note: String,
        occurredAt: Date
    ) throws -> LedgerEntry {
        try update(
            entry,
            kind: kind,
            amountMinor: amountMinor,
            feeMinor: feeMinor,
            account: account,
            lines: Self.singleLine(kind: kind, amountMinor: amountMinor, category: category),
            payee: payee,
            note: note,
            occurredAt: occurredAt
        )
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

    // MARK: - Lines

    private static func singleLine(
        kind: LedgerEntryKind,
        amountMinor: Int64,
        category: SpendingCategory?
    ) -> [LedgerLineInput] {
        guard kind == .expense || kind == .income else {
            return []
        }

        return [LedgerLineInput(amountMinor: amountMinor, category: category)]
    }

    private func validate(lines: [LedgerLineInput], kind: LedgerEntryKind, amountMinor: Int64) throws {
        guard kind == .expense || kind == .income else {
            guard lines.isEmpty else {
                throw LedgerError.linesNotAllowed
            }

            return
        }

        guard !lines.isEmpty else {
            throw LedgerError.linesRequired
        }

        for line in lines {
            guard line.amountMinor > 0 else {
                throw LedgerError.lineAmountInvalid
            }

            if let category = line.category, category.kind != kind.categoryKind {
                throw LedgerError.lineCategoryMismatch
            }
        }

        let total = lines.reduce(Int64(0)) { $0 + $1.amountMinor }

        guard total == amountMinor else {
            throw LedgerError.linesDoNotMatchTotal(expectedMinor: amountMinor, actualMinor: total)
        }
    }

    private func replaceLines(on entry: LedgerEntry, with inputs: [LedgerLineInput]) {
        for line in entry.lines ?? [] {
            context.delete(line)
        }

        var created: [LedgerEntryLine] = []

        for (index, input) in inputs.enumerated() {
            let line = LedgerEntryLine(
                amountMinor: input.amountMinor,
                sortIndex: index,
                category: input.category,
                tags: input.tags
            )
            context.insert(line)
            line.entry = entry
            created.append(line)
        }

        entry.lines = created
    }

    private func singleCategory(in lines: [LedgerLineInput]) -> SpendingCategory? {
        let categories = Set(lines.compactMap { $0.category?.id })

        guard categories.count == 1 else {
            return nil
        }

        return lines.compactMap(\.category).first
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

    /// Every entry the transactions screen can show, newest first.
    public func transactions() throws -> [LedgerEntry] {
        try context.fetch(
            FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> {
                    !$0.isSoftDeleted && $0.kindRaw != "openingBalance" && $0.statusRaw != "ignored"
                },
                sortBy: [
                    SortDescriptor(\LedgerEntry.occurredAt, order: .reverse),
                    SortDescriptor(\LedgerEntry.createdAt, order: .reverse),
                ]
            )
        )
    }

    public func balance(for account: Account) -> Money {
        Money(minorUnits: AccountBalance.balanceMinor(for: account), currency: account.currency)
    }
}
