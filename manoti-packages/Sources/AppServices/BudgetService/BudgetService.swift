//
//  BudgetService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum BudgetError: Error, Equatable {
    case invalidLimit
    case archivedCategory
    case incomeCategory
}

/// One envelope's numbers for a period, in the summary's display currency.
nonisolated public struct EnvelopeSummary: Identifiable, Equatable, Sendable {
    public let envelopeID: UUID
    public let categoryID: UUID?
    public let categoryName: String
    public let symbolName: String
    public let colorHex: String
    public let isFixed: Bool
    public let isArchived: Bool
    public let limit: Money
    public let spent: Money
    public let rollover: Money
    public let remaining: Money
    public let missingRates: [String]

    public var id: UUID { envelopeID }

    public init(
        envelopeID: UUID,
        categoryID: UUID?,
        categoryName: String,
        symbolName: String,
        colorHex: String,
        isFixed: Bool,
        isArchived: Bool,
        limit: Money,
        spent: Money,
        rollover: Money,
        remaining: Money,
        missingRates: [String]
    ) {
        self.envelopeID = envelopeID
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.isFixed = isFixed
        self.isArchived = isArchived
        self.limit = limit
        self.spent = spent
        self.rollover = rollover
        self.remaining = remaining
        self.missingRates = missingRates
    }
}

/// Totals for one period in one display currency.
///
/// `totalSpent` counts only envelope categories; spending outside every envelope is
/// reported separately in `unbudgeted` so it is never silently folded into a limit.
nonisolated public struct BudgetSummary: Equatable, Sendable {
    public let periodID: UUID
    public let kind: BudgetPeriodKind
    public let startDate: Date
    public let endDate: Date
    public let currency: Currency
    public let totalLimit: Money
    public let totalSpent: Money
    public let remaining: Money
    public let unbudgeted: Money
    public let fixedLimit: Money
    public let fixedSpent: Money
    public let variableLimit: Money
    public let variableSpent: Money
    public let rollover: Money
    public let envelopes: [EnvelopeSummary]
    public let missingRates: [String]
    public let totalDays: Int
    public let elapsedDays: Int
    public let daysRemaining: Int
    public let projectedSpend: Money

    public init(
        periodID: UUID,
        kind: BudgetPeriodKind,
        startDate: Date,
        endDate: Date,
        currency: Currency,
        totalLimit: Money,
        totalSpent: Money,
        remaining: Money,
        unbudgeted: Money,
        fixedLimit: Money,
        fixedSpent: Money,
        variableLimit: Money,
        variableSpent: Money,
        rollover: Money,
        envelopes: [EnvelopeSummary],
        missingRates: [String],
        totalDays: Int,
        elapsedDays: Int,
        daysRemaining: Int,
        projectedSpend: Money
    ) {
        self.periodID = periodID
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.currency = currency
        self.totalLimit = totalLimit
        self.totalSpent = totalSpent
        self.remaining = remaining
        self.unbudgeted = unbudgeted
        self.fixedLimit = fixedLimit
        self.fixedSpent = fixedSpent
        self.variableLimit = variableLimit
        self.variableSpent = variableSpent
        self.rollover = rollover
        self.envelopes = envelopes
        self.missingRates = missingRates
        self.totalDays = totalDays
        self.elapsedDays = elapsedDays
        self.daysRemaining = daysRemaining
        self.projectedSpend = projectedSpend
    }

    /// Every confirmed expense in the period, budgeted or not.
    public var totalOutflow: Money {
        let (sum, overflow) = totalSpent.minorUnits.addingReportingOverflow(unbudgeted.minorUnits)
        return Money(
            minorUnits: overflow ? Int64.max : sum,
            currency: totalSpent.currency
        )
    }
}

/// What is left to spend on flexible categories, spread over the remaining days.
nonisolated public struct SafeToSpend: Equatable, Sendable {
    public let amount: Money
    public let daysRemaining: Int
    public let discretionaryRemaining: Money

    public init(amount: Money, daysRemaining: Int, discretionaryRemaining: Money) {
        self.amount = amount
        self.daysRemaining = daysRemaining
        self.discretionaryRemaining = discretionaryRemaining
    }
}

/// A file-scope accumulator for one period's spending, already converted to the display
/// currency.
private struct BudgetActuals {
    var byCategory: [UUID: Int64] = [:]
    var missingByCategory: [UUID: Set<String>] = [:]
    var uncategorizedMinor: Int64 = 0
    var totalMinor: Int64 = 0
    var missingRates: Set<String> = []
}

/// Periods, envelopes and the calculations behind the budget dashboard.
///
/// Actual spending always comes from the ledger. Only confirmed, non-ignored, non-deleted
/// `.expense` rows count; transfers, loan cash and investment cash are ignored even when a
/// row happens to carry the expense kind.
@Observable
nonisolated public final class BudgetService: Loggable {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - Periods

    /// Returns the period containing `date`, creating exactly one row the first time.
    ///
    /// Weeks follow `calendar.firstWeekday`; apply `AppSettings.weekStartsOn` before calling
    /// when the user has chosen a different start day.
    @discardableResult
    public func currentPeriod(kind: BudgetPeriodKind, containing date: Date, calendar: Calendar) throws -> BudgetPeriod
    {
        let interval = kind.dateInterval(containing: date, calendar: calendar)
        return try period(kind: kind, startDate: interval.start, endDate: interval.end)
    }

    /// The existing period for `date`, without creating a row. Read-only paths such as the
    /// widget snapshot must not mutate the store.
    public func currentPeriodIfExists(
        kind: BudgetPeriodKind,
        containing date: Date,
        calendar: Calendar
    ) throws -> BudgetPeriod? {
        let interval = kind.dateInterval(containing: date, calendar: calendar)
        let kindRaw = kind.rawValue
        let startDate = interval.start
        var descriptor = FetchDescriptor<BudgetPeriod>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.startDate == startDate },
            sortBy: [SortDescriptor(\BudgetPeriod.createdAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func period(kind: BudgetPeriodKind, startDate: Date, endDate: Date) throws -> BudgetPeriod {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<BudgetPeriod>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.startDate == startDate },
            sortBy: [SortDescriptor(\BudgetPeriod.createdAt)]
        )

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let created = BudgetPeriod(kind: kind, startDate: startDate, endDate: endDate)
        context.insert(created)
        try context.save()
        ManotiNotifications.postDataChanged()
        log("Created \(kind.rawValue) budget period", level: .info)
        return created
    }

    // MARK: - Envelopes

    public func envelopes(for period: BudgetPeriod) throws -> [Envelope] {
        let periodID = period.id
        let descriptor = FetchDescriptor<Envelope>(
            predicate: #Predicate { $0.period?.id == periodID }
        )

        return try context.fetch(descriptor).sorted(by: envelopeOrder)
    }

    /// The period immediately before `period` of the same kind, if one exists.
    ///
    /// This only reads existing rows; the editor uses it to suggest a limit from last
    /// period's actual spending without creating a period as a side effect.
    public func previousPeriod(for period: BudgetPeriod) throws -> BudgetPeriod? {
        let kindRaw = period.kindRaw
        let startDate = period.startDate
        let descriptor = FetchDescriptor<BudgetPeriod>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.endDate == startDate },
            sortBy: [SortDescriptor(\BudgetPeriod.startDate, order: .reverse)]
        )

        return try context.fetch(descriptor).first
    }

    /// Creates or updates the one envelope for `category` in `period`.
    @discardableResult
    public func setEnvelope(
        category: SpendingCategory,
        limitMinor: Int64,
        rolloverEnabled: Bool,
        note: String? = nil,
        in period: BudgetPeriod
    ) throws -> Envelope {
        guard limitMinor >= 0 else {
            throw BudgetError.invalidLimit
        }

        guard !category.isArchived else {
            throw BudgetError.archivedCategory
        }

        guard category.kind == .expense else {
            throw BudgetError.incomeCategory
        }

        let periodID = period.id
        let categoryID = category.id
        let descriptor = FetchDescriptor<Envelope>(
            predicate: #Predicate { $0.period?.id == periodID && $0.category?.id == categoryID },
            sortBy: [SortDescriptor(\Envelope.createdAt)]
        )

        if let existing = try context.fetch(descriptor).first {
            existing.limitMinor = limitMinor
            existing.rolloverEnabled = rolloverEnabled
            existing.isArchived = false
            if let note {
                existing.note = note
            }
            try context.save()
            ManotiNotifications.postDataChanged()
            return existing
        }

        let envelope = Envelope(
            period: period,
            category: category,
            limitMinor: limitMinor,
            currencyCode: displayCurrencyCode(),
            rolloverEnabled: rolloverEnabled,
            note: note ?? ""
        )
        context.insert(envelope)
        try context.save()
        ManotiNotifications.postDataChanged()
        log("Set \(category.name) envelope to \(limitMinor)", level: .info)
        return envelope
    }

    // MARK: - Actuals

    /// Confirmed spending in `category` during `period`, in the app's display currency.
    public func actualMinor(for category: SpendingCategory, in period: BudgetPeriod) throws -> Int64 {
        let displayCurrency = CurrencyCatalog.currency(for: displayCurrencyCode())
        let actuals = try actuals(in: period, displayCurrency: displayCurrency)
        return actuals.byCategory[category.id] ?? 0
    }

    // MARK: - Summary

    public func summary(
        for period: BudgetPeriod,
        displayCurrency: Currency,
        now: Date = Date()
    ) throws -> BudgetSummary {
        let book = try rateBook()
        let actuals = try actuals(in: period, displayCurrency: displayCurrency, book: book)
        let envelopes = try uniqueEnvelopes(for: period)

        var missingRates = actuals.missingRates
        var rows: [EnvelopeSummary] = []
        var budgetedCategoryIDs: Set<UUID> = []

        var totalLimit: Int64 = 0
        var totalSpent: Int64 = 0
        var totalRollover: Int64 = 0
        var fixedLimit: Int64 = 0
        var fixedSpent: Int64 = 0
        var variableLimit: Int64 = 0
        var variableSpent: Int64 = 0

        for envelope in envelopes {
            guard let category = envelope.category else {
                continue
            }

            budgetedCategoryIDs.insert(category.id)

            let spent = actuals.byCategory[category.id] ?? 0
            var visited: Set<UUID> = []
            let rollover = try carriedMinor(
                for: envelope,
                displayCurrency: displayCurrency,
                book: book,
                visited: &visited,
                missingRates: &missingRates
            )
            let limit = convertedLimitMinor(
                for: envelope,
                displayCurrency: displayCurrency,
                book: book,
                missingRates: &missingRates
            )
            let remaining = limit + rollover - spent

            totalLimit += limit
            totalSpent += spent
            totalRollover += rollover

            if category.isFixed {
                fixedLimit += limit
                fixedSpent += spent
            } else {
                variableLimit += limit
                variableSpent += spent
            }

            rows.append(
                EnvelopeSummary(
                    envelopeID: envelope.id,
                    categoryID: category.id,
                    categoryName: category.name,
                    symbolName: category.symbolName,
                    colorHex: category.colorHex,
                    isFixed: category.isFixed,
                    isArchived: envelope.isArchived,
                    limit: Money(minorUnits: limit, currency: displayCurrency),
                    spent: Money(minorUnits: spent, currency: displayCurrency),
                    rollover: Money(minorUnits: rollover, currency: displayCurrency),
                    remaining: Money(minorUnits: remaining, currency: displayCurrency),
                    missingRates: (actuals.missingByCategory[category.id] ?? []).sorted()
                )
            )
        }

        let unbudgeted = unbudgetedMinor(actuals: actuals, budgetedCategoryIDs: budgetedCategoryIDs)
        let counts = dayCounts(for: period, now: now, calendar: calendar)
        let projected = projectedSpendMinor(
            spentMinor: totalSpent,
            totalDays: counts.totalDays,
            elapsedDays: counts.elapsedDays
        )

        return BudgetSummary(
            periodID: period.id,
            kind: period.kind,
            startDate: period.startDate,
            endDate: period.endDate,
            currency: displayCurrency,
            totalLimit: Money(minorUnits: totalLimit, currency: displayCurrency),
            totalSpent: Money(minorUnits: totalSpent, currency: displayCurrency),
            remaining: Money(minorUnits: totalLimit + totalRollover - totalSpent, currency: displayCurrency),
            unbudgeted: Money(minorUnits: unbudgeted, currency: displayCurrency),
            fixedLimit: Money(minorUnits: fixedLimit, currency: displayCurrency),
            fixedSpent: Money(minorUnits: fixedSpent, currency: displayCurrency),
            variableLimit: Money(minorUnits: variableLimit, currency: displayCurrency),
            variableSpent: Money(minorUnits: variableSpent, currency: displayCurrency),
            rollover: Money(minorUnits: totalRollover, currency: displayCurrency),
            envelopes: rows,
            missingRates: missingRates.sorted(),
            totalDays: counts.totalDays,
            elapsedDays: counts.elapsedDays,
            daysRemaining: counts.daysRemaining,
            projectedSpend: Money(minorUnits: projected, currency: displayCurrency)
        )
    }

    /// Flexible-category money left, divided by the remaining days. Never negative and never
    /// divides by zero.
    public func safeToSpend(
        for period: BudgetPeriod,
        displayCurrency: Currency,
        now: Date = Date()
    ) throws -> SafeToSpend {
        let summary = try summary(for: period, displayCurrency: displayCurrency, now: now)
        let discretionary = summary.envelopes.reduce(Int64(0)) { total, row in
            guard !row.isFixed, row.limit.minorUnits > 0 else {
                return total
            }

            return total + row.remaining.minorUnits
        }
        let positive = max(0, discretionary)
        let amount = summary.daysRemaining > 0 ? positive / Int64(summary.daysRemaining) : 0

        return SafeToSpend(
            amount: Money(minorUnits: amount, currency: displayCurrency),
            daysRemaining: summary.daysRemaining,
            discretionaryRemaining: Money(minorUnits: positive, currency: displayCurrency)
        )
    }

    // MARK: - Rollover

    /// One row per category. A merge or sync can leave two rows for the same period; the
    /// newest wins instead of counting the same limit and spending twice.
    private func uniqueEnvelopes(for period: BudgetPeriod) throws -> [Envelope] {
        let all = try envelopes(for: period)
        var newest: [UUID: Envelope] = [:]

        for envelope in all {
            guard let categoryID = envelope.category?.id else {
                continue
            }

            if let existing = newest[categoryID], existing.createdAt >= envelope.createdAt {
                continue
            }

            newest[categoryID] = envelope
        }

        return newest.values.sorted(by: envelopeOrder)
    }

    /// Converts a stored limit into the display currency at the period's start. A missing
    /// rate falls back 1:1 and is reported, exactly like an entry conversion.
    private func convertedLimitMinor(
        for envelope: Envelope,
        displayCurrency: Currency,
        book: ExchangeRateBook,
        missingRates: inout Set<String>
    ) -> Int64 {
        let stored = envelope.limit
        let date = envelope.period?.startDate ?? envelope.createdAt

        if let converted = book.convert(stored, to: displayCurrency, on: date) {
            return converted.minorUnits
        }

        if stored.currency == displayCurrency {
            return stored.minorUnits
        }

        missingRates.insert(stored.currency.code)
        return fallback(stored, to: displayCurrency).minorUnits
    }

    /// The prior period's remaining amount, but only when this envelope allows rollover.
    private func carriedMinor(
        for envelope: Envelope,
        displayCurrency: Currency,
        book: ExchangeRateBook,
        visited: inout Set<UUID>,
        missingRates: inout Set<String>
    ) throws -> Int64 {
        guard envelope.rolloverEnabled else {
            return 0
        }

        guard let previous = try previousEnvelope(for: envelope) else {
            return 0
        }

        return try remainingMinor(
            for: previous,
            displayCurrency: displayCurrency,
            book: book,
            visited: &visited,
            missingRates: &missingRates
        )
    }

    private func remainingMinor(
        for envelope: Envelope,
        displayCurrency: Currency,
        book: ExchangeRateBook,
        visited: inout Set<UUID>,
        missingRates: inout Set<String>
    ) throws -> Int64 {
        guard !visited.contains(envelope.id) else {
            return 0
        }
        visited.insert(envelope.id)

        let carried = try carriedMinor(
            for: envelope,
            displayCurrency: displayCurrency,
            book: book,
            visited: &visited,
            missingRates: &missingRates
        )
        let spent = try spentMinor(
            for: envelope,
            displayCurrency: displayCurrency,
            book: book,
            missingRates: &missingRates
        )
        let limit = convertedLimitMinor(
            for: envelope,
            displayCurrency: displayCurrency,
            book: book,
            missingRates: &missingRates
        )

        return limit + carried - spent
    }

    private func previousEnvelope(for envelope: Envelope) throws -> Envelope? {
        guard let period = envelope.period, let category = envelope.category else {
            return nil
        }

        let kindRaw = period.kindRaw
        let startDate = period.startDate
        let periodDescriptor = FetchDescriptor<BudgetPeriod>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.endDate == startDate },
            sortBy: [SortDescriptor(\BudgetPeriod.startDate, order: .reverse)]
        )

        guard let previousPeriod = try context.fetch(periodDescriptor).first else {
            return nil
        }

        let periodID = previousPeriod.id
        let categoryID = category.id
        let descriptor = FetchDescriptor<Envelope>(
            predicate: #Predicate { $0.period?.id == periodID && $0.category?.id == categoryID },
            sortBy: [SortDescriptor(\Envelope.createdAt)]
        )

        return try context.fetch(descriptor).first
    }

    private func spentMinor(
        for envelope: Envelope,
        displayCurrency: Currency,
        book: ExchangeRateBook,
        missingRates: inout Set<String>
    ) throws -> Int64 {
        guard let period = envelope.period, let category = envelope.category else {
            return 0
        }

        let actuals = try actuals(in: period, displayCurrency: displayCurrency, book: book)
        missingRates.formUnion(actuals.missingRates)
        return actuals.byCategory[category.id] ?? 0
    }

    // MARK: - Ledger

    private func actuals(
        in period: BudgetPeriod,
        displayCurrency: Currency,
        book: ExchangeRateBook? = nil
    ) throws -> BudgetActuals {
        let rates: ExchangeRateBook
        if let book {
            rates = book
        } else {
            rates = try rateBook()
        }

        let start = period.startDate
        let end = period.endDate
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate {
                !$0.isSoftDeleted && $0.kindRaw == "expense" && $0.statusRaw == "confirmed"
                    && $0.occurredAt >= start && $0.occurredAt < end
            }
        )

        var result = BudgetActuals()

        for entry in try context.fetch(descriptor) {
            guard entry.transfer == nil, entry.loan == nil, entry.investmentCashFlow == nil else {
                continue
            }

            let amount = Money(minorUnits: abs(entry.signedAmountMinor), currency: entry.currency)
            let converted: Money
            let missingCurrency: String?
            if let value = rates.convert(amount, to: displayCurrency, on: entry.occurredAt) {
                converted = value
                // Same-currency entries need no rate, so they never report a missing one.
                missingCurrency = nil
            } else {
                missingCurrency = entry.currency.code
                result.missingRates.insert(entry.currency.code)
                converted = fallback(amount, to: displayCurrency)
            }

            result.totalMinor += converted.minorUnits

            if let categoryID = entry.category?.id {
                result.byCategory[categoryID, default: 0] += converted.minorUnits
                if let missingCurrency {
                    result.missingByCategory[categoryID, default: []].insert(missingCurrency)
                }
            } else {
                result.uncategorizedMinor += converted.minorUnits
            }
        }

        return result
    }

    private func unbudgetedMinor(actuals: BudgetActuals, budgetedCategoryIDs: Set<UUID>) -> Int64 {
        actuals.byCategory.reduce(actuals.uncategorizedMinor) { total, pair in
            budgetedCategoryIDs.contains(pair.key) ? total : total + pair.value
        }
    }

    // MARK: - Environment

    public func rateBook() throws -> ExchangeRateBook {
        let records = try context.fetch(
            FetchDescriptor<ExchangeRateRecord>(sortBy: [SortDescriptor(\ExchangeRateRecord.asOf, order: .reverse)])
        )
        return ExchangeRateBook(records: records, calendar: calendar)
    }

    private func displayCurrencyCode() -> String {
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            return settings.displayCurrencyCode
        }

        return CurrencyCatalog.defaultCurrency.code
    }

    /// Reinterprets the major-unit amount in the display currency when no rate is known, so a
    /// missing rate is shown 1:1 rather than silently blended.
    private func fallback(_ money: Money, to currency: Currency) -> Money {
        Money(decimal: money.decimalValue, currency: currency) ?? .zero(in: currency)
    }

    private func envelopeOrder(_ lhs: Envelope, _ rhs: Envelope) -> Bool {
        let leftIndex = lhs.category?.sortIndex ?? Int.max
        let rightIndex = rhs.category?.sortIndex ?? Int.max

        if leftIndex != rightIndex {
            return leftIndex < rightIndex
        }

        let leftName = lhs.category?.name ?? ""
        let rightName = rhs.category?.name ?? ""

        if leftName != rightName {
            return leftName < rightName
        }

        return lhs.createdAt < rhs.createdAt
    }
}
