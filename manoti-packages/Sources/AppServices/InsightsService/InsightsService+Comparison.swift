//
//  InsightsService+Comparison.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

public enum InsightsError: Error, Equatable, Sendable {
    case invalidPeriod
}

extension InsightsService {
    /// Compares the period containing `date` with the previous equal-elapsed period and with
    /// up to four preceding periods.
    ///
    /// The current window runs from the period start through the same clock time as `date`.
    /// The previous window is day-granular and covers the same number of whole elapsed days,
    /// capped at the previous period's length. Only confirmed expenses count, converted at
    /// each entry's own date.
    ///
    /// A preceding period is comparable when it contains at least one posted entry of any
    /// kind; a month with no rows at all is treated as missing history rather than as a real
    /// zero. The trailing average needs two comparable periods.
    public func comparison(
        kind: InsightPeriodKind,
        containing date: Date = Date(),
        displayCurrency: Currency,
        calendar: Calendar = .current,
        smallSpendThresholdMinor: Int64? = nil
    ) throws -> SpendComparison {
        guard let windows = ComparisonWindows(kind: kind, containing: date, calendar: calendar) else {
            throw InsightsError.invalidPeriod
        }

        let trailing = precedingPeriods(
            kind: kind,
            before: windows.current.start,
            elapsedDays: windows.elapsedDays,
            count: 4,
            calendar: calendar
        )
        let rangeStart = trailing.last?.full.start ?? windows.previous.start
        let rangeEnd = windows.current.end
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                $0.occurredAt >= rangeStart && $0.occurredAt < rangeEnd
            }
        )
        let entries = try context.fetch(descriptor).sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt < rhs.occurredAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }

        let book = try exchangeRateBook(calendar: calendar)
        var accumulators = Array(repeating: SpendAccumulator(), count: trailing.count + 1)

        for entry in entries where isSpending(entry) {
            guard let index = accumulatorIndex(for: entry.occurredAt, windows: windows, trailing: trailing) else {
                continue
            }

            let converted = convert(entry, to: displayCurrency, book: book)
            let dayOffset =
                calendar.dateComponents(
                    [.day],
                    from: index == 0 ? windows.current.start : trailing[index - 1].window.start,
                    to: calendar.startOfDay(for: entry.occurredAt)
                ).day ?? 0
            let category = entry.category
            let meta = category.map {
                CategoryMeta(name: $0.name, symbolName: $0.symbolName, colorHex: $0.colorHex)
            }
            let payee = entry.payee.trimmingCharacters(in: .whitespacesAndNewlines)

            accumulators[index].add(
                minorUnits: converted.minorUnits,
                categoryID: category?.id,
                meta: meta,
                isFixed: category?.isFixed == true,
                payee: payee,
                dayOffset: max(0, dayOffset),
                missingCurrency: converted.missingCurrency
            )
        }

        var sampleCount = 0
        var sampleSum: Int64 = 0
        var sampledIndices: Set<Int> = []

        for (offset, period) in trailing.enumerated() {
            let hasData = entries.contains { entry in
                entry.isPosted && entry.occurredAt >= period.full.start && entry.occurredAt < period.full.end
            }
            guard hasData else {
                continue
            }

            let index = offset + 1
            sampleCount += 1
            sampleSum += accumulators[index].totalMinor
            sampledIndices.insert(index)
        }

        let current = accumulators[0]
        let previous = accumulators[1]
        let threshold = smallSpendThresholdMinor ?? defaultSmallSpendThreshold(for: displayCurrency)
        let smallSpends = makeSmallFrequentSpends(
            from: current.entries,
            thresholdMinor: threshold,
            currency: displayCurrency
        )

        var missing: Set<String> = current.missingRates.union(previous.missingRates)
        for index in sampledIndices {
            missing.formUnion(accumulators[index].missingRates)
        }

        let trailingAverage: Money? =
            sampleCount >= 2
            ? Money(minorUnits: roundedMean(sampleSum, count: sampleCount), currency: displayCurrency)
            : nil

        let insufficientHistoryMessage: String? =
            sampleCount >= 2 ? nil : "Not enough data yet (\(sampleCount) of 2 periods)"

        return SpendComparison(
            kind: kind,
            currentInterval: windows.current,
            previousInterval: windows.previous,
            elapsedDays: windows.elapsedDays,
            currentTotal: Money(minorUnits: current.totalMinor, currency: displayCurrency),
            previousTotal: Money(minorUnits: previous.totalMinor, currency: displayCurrency),
            trailingAverage: trailingAverage,
            trailingSampleCount: sampleCount,
            percentChange: percentChange(from: previous.totalMinor, to: current.totalMinor),
            fixedCurrent: Money(minorUnits: current.fixedMinor, currency: displayCurrency),
            fixedPrevious: Money(minorUnits: previous.fixedMinor, currency: displayCurrency),
            variableCurrent: Money(minorUnits: current.variableMinor, currency: displayCurrency),
            variablePrevious: Money(minorUnits: previous.variableMinor, currency: displayCurrency),
            categoryDeltas: categoryDeltas(current: current, previous: previous, currency: displayCurrency),
            dailyPoints: dailyPoints(
                window: windows,
                current: current,
                previous: previous,
                currency: displayCurrency,
                calendar: calendar
            ),
            topMerchants: merchantSpends(from: current.byPayee, limit: 5, currency: displayCurrency),
            smallFrequent: smallSpends,
            balanceDrift: try balanceDrift(),
            missingRates: missing.sorted(),
            insufficientHistoryMessage: insufficientHistoryMessage
        )
    }

    // MARK: - Ledger rules

    /// Confirmed expense rows only. Transfer, loan and investment legs never count as
    /// spending, even if they somehow carry the expense kind.
    private func isSpending(_ entry: LedgerEntry) -> Bool {
        guard entry.kind == .expense, entry.status == .confirmed, !entry.isSoftDeleted else {
            return false
        }

        return entry.transfer == nil && entry.loan == nil && entry.investmentCashFlow == nil
    }

    private func accumulatorIndex(
        for occurredAt: Date,
        windows: ComparisonWindows,
        trailing: [TrailingPeriod]
    ) -> Int? {
        if occurredAt >= windows.current.start && occurredAt < windows.current.end {
            return 0
        }

        for (offset, period) in trailing.enumerated()
        where occurredAt >= period.window.start && occurredAt < period.window.end {
            return offset + 1
        }

        return nil
    }

    private func exchangeRateBook(calendar: Calendar) throws -> ExchangeRateBook {
        let records = try context.fetch(
            FetchDescriptor<ExchangeRateRecord>(sortBy: [SortDescriptor(\ExchangeRateRecord.asOf, order: .reverse)])
        )
        return ExchangeRateBook(records: records, calendar: calendar)
    }

    private func convert(
        _ entry: LedgerEntry,
        to displayCurrency: Currency,
        book: ExchangeRateBook
    ) -> (minorUnits: Int64, missingCurrency: String?) {
        let amount = Money(minorUnits: abs(entry.signedAmountMinor), currency: entry.currency)

        if let converted = book.convert(amount, to: displayCurrency, on: entry.occurredAt) {
            // Same-currency entries need no rate, so they never report a missing one.
            return (converted.minorUnits, nil)
        }

        let fallbackAmount = fallback(amount, to: displayCurrency)
        return (fallbackAmount.minorUnits, entry.currency.code)
    }

    // MARK: - Category deltas

    /// Categories with spending in either window. Uncategorised spending appears in the
    /// totals and the fixed/variable split but has no category row of its own.
    private func categoryDeltas(
        current: SpendAccumulator,
        previous: SpendAccumulator,
        currency: Currency
    ) -> [CategorySpendDelta] {
        let categoryIDs = Set(current.byCategory.keys).union(previous.byCategory.keys)
        var rows: [CategorySpendDelta] = []

        for categoryID in categoryIDs {
            guard let meta = current.categoryMeta[categoryID] ?? previous.categoryMeta[categoryID] else {
                continue
            }

            let currentMinor = current.byCategory[categoryID] ?? 0
            let previousMinor = previous.byCategory[categoryID] ?? 0
            rows.append(
                CategorySpendDelta(
                    categoryID: categoryID,
                    name: meta.name,
                    symbolName: meta.symbolName,
                    colorHex: meta.colorHex,
                    current: Money(minorUnits: currentMinor, currency: currency),
                    previous: Money(minorUnits: previousMinor, currency: currency),
                    difference: Money(minorUnits: currentMinor - previousMinor, currency: currency),
                    percentChange: percentChange(from: previousMinor, to: currentMinor)
                )
            )
        }

        rows.sort { lhs, rhs in
            let leftDifference = abs(lhs.difference.minorUnits)
            let rightDifference = abs(rhs.difference.minorUnits)

            if leftDifference != rightDifference {
                return leftDifference > rightDifference
            }

            if lhs.name != rhs.name {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.categoryID.uuidString < rhs.categoryID.uuidString
        }

        return rows
    }

    // MARK: - Daily points

    private func dailyPoints(
        window: ComparisonWindows,
        current: SpendAccumulator,
        previous: SpendAccumulator,
        currency: Currency,
        calendar: Calendar
    ) -> [DailyComparisonPoint] {
        (1...window.elapsedDays).compactMap { dayIndex in
            guard let currentDate = calendar.date(byAdding: .day, value: dayIndex - 1, to: window.current.start) else {
                return nil
            }

            return DailyComparisonPoint(
                dayIndex: dayIndex,
                currentDate: currentDate,
                current: Money(minorUnits: current.byDay[dayIndex - 1] ?? 0, currency: currency),
                previous: Money(minorUnits: previous.byDay[dayIndex - 1] ?? 0, currency: currency)
            )
        }
    }

    // MARK: - Merchants

    private func merchantSpends(
        from tallies: [String: PayeeTally],
        limit: Int,
        currency: Currency
    ) -> [MerchantSpend] {
        tallies.values
            .map {
                MerchantSpend(
                    payee: $0.payee,
                    count: $0.count,
                    total: Money(minorUnits: $0.totalMinor, currency: currency)
                )
            }
            .sorted { lhs, rhs in
                if lhs.total.minorUnits != rhs.total.minorUnits {
                    return lhs.total.minorUnits > rhs.total.minorUnits
                }

                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }

                return lhs.payee.localizedCaseInsensitiveCompare(rhs.payee) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Small frequent spends

    private func makeSmallFrequentSpends(
        from entries: [SpendEntry],
        thresholdMinor: Int64,
        currency: Currency
    ) -> SmallFrequentSpends? {
        let small = entries.filter { $0.minorUnits > 0 && $0.minorUnits <= thresholdMinor }
        guard !small.isEmpty else {
            return nil
        }

        var tallies: [String: PayeeTally] = [:]

        for entry in small where !entry.payee.isEmpty {
            tallies.add(minorUnits: entry.minorUnits, payee: entry.payee)
        }

        let topPayees = tallies.values
            .filter { $0.count >= 2 }
            .map {
                MerchantSpend(
                    payee: $0.payee,
                    count: $0.count,
                    total: Money(minorUnits: $0.totalMinor, currency: currency)
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }

                if lhs.total.minorUnits != rhs.total.minorUnits {
                    return lhs.total.minorUnits > rhs.total.minorUnits
                }

                return lhs.payee.localizedCaseInsensitiveCompare(rhs.payee) == .orderedAscending
            }
            .prefix(3)
            .map { $0 }

        return SmallFrequentSpends(
            count: small.count,
            total: Money(minorUnits: small.reduce(Int64(0)) { $0 + $1.minorUnits }, currency: currency),
            threshold: Money(minorUnits: thresholdMinor, currency: currency),
            topPayees: topPayees
        )
    }

    private func defaultSmallSpendThreshold(for currency: Currency) -> Int64 {
        var units: Int64 = 1

        for _ in 0..<currency.exponent {
            units *= 10
        }

        return 500 * units
    }

    // MARK: - Balance drift

    /// Compares each account's computed balance with the last balance the bank reported.
    ///
    /// The ledger balance at that message is the account's current balance minus every posted
    /// entry that happened strictly after it. Nothing is written back.
    private func balanceDrift() throws -> [BalanceDrift] {
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { !$0.isArchived }
        var rows: [BalanceDrift] = []

        for account in accounts {
            let posted = (account.transactions ?? []).filter(\.isPosted)
            guard
                let anchor = posted.filter({ $0.balanceAfterMinor != nil }).max(by: { lhs, rhs in
                    if lhs.occurredAt != rhs.occurredAt {
                        return lhs.occurredAt < rhs.occurredAt
                    }

                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }

                    return lhs.id.uuidString < rhs.id.uuidString
                }),
                let reportedMinor = anchor.balanceAfterMinor
            else {
                continue
            }

            let laterChange = posted.reduce(Int64(0)) { total, entry in
                entry.occurredAt > anchor.occurredAt ? total + entry.signedAmountMinor : total
            }
            let ledgerMinor = account.balance.minorUnits - laterChange
            let differenceMinor = ledgerMinor - reportedMinor
            guard differenceMinor != 0 else {
                continue
            }

            rows.append(
                BalanceDrift(
                    accountID: account.id,
                    name: account.displayName,
                    reportedBalance: Money(minorUnits: reportedMinor, currency: account.currency),
                    ledgerBalance: Money(minorUnits: ledgerMinor, currency: account.currency),
                    difference: Money(minorUnits: differenceMinor, currency: account.currency),
                    asOf: anchor.occurredAt
                )
            )
        }

        rows.sort { lhs, rhs in
            let leftDifference = abs(lhs.difference.minorUnits)
            let rightDifference = abs(rhs.difference.minorUnits)

            if leftDifference != rightDifference {
                return leftDifference > rightDifference
            }

            if lhs.name != rhs.name {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.accountID.uuidString < rhs.accountID.uuidString
        }

        return rows
    }

    // MARK: - Maths

    /// Percentage change, or `nil` when there is no previous amount to divide by.
    private func percentChange(from previous: Int64, to current: Int64) -> Double? {
        guard previous != 0 else {
            return nil
        }

        return Double(current - previous) / Double(previous) * 100
    }

    /// Rounds half up to the nearest minor unit. All inputs here are non-negative.
    private func roundedMean(_ sum: Int64, count: Int) -> Int64 {
        let divisor = Int64(count)
        let quotient = sum / divisor
        let remainder = sum % divisor
        return remainder * 2 >= divisor ? quotient + 1 : quotient
    }
}

// MARK: - Windows

private struct ComparisonWindows: Equatable, Sendable {
    let current: DateInterval
    let previous: DateInterval
    let elapsedDays: Int

    init?(kind: InsightPeriodKind, containing date: Date, calendar: Calendar) {
        guard let period = calendar.dateInterval(of: kind.component, for: date) else {
            return nil
        }

        let start = calendar.startOfDay(for: period.start)
        let end = calendar.startOfDay(for: period.end)
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let today = calendar.startOfDay(for: date)
        let dayIndex = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
        let elapsedDays = min(totalDays, max(1, dayIndex + 1))

        // The current window runs through the same clock time as `date`; the previous window
        // is day-granular, so it ends after the same number of whole elapsed days.
        let currentEnd = min(date, period.end)

        guard
            let previousDay = calendar.date(byAdding: .day, value: -1, to: start),
            let previousPeriod = calendar.dateInterval(of: kind.component, for: previousDay)
        else {
            return nil
        }

        let previousStart = calendar.startOfDay(for: previousPeriod.start)
        let previousEndOfPeriod = calendar.startOfDay(for: previousPeriod.end)

        // Compare the same amount of clock time, not whole previous days: otherwise an
        // evening purchase on the same day last month is compared with a partial today.
        let elapsed = currentEnd.timeIntervalSince(start)
        let rawPreviousEnd = previousStart.addingTimeInterval(max(0, elapsed))
        let previousEnd = min(rawPreviousEnd, previousEndOfPeriod)

        self.current = DateInterval(start: start, end: currentEnd)
        self.previous = DateInterval(start: previousStart, end: previousEnd)
        self.elapsedDays = elapsedDays
    }
}

private struct TrailingPeriod: Equatable, Sendable {
    /// The whole preceding period, used only to decide whether the app has data for it.
    let full: DateInterval

    /// The same number of elapsed days as the current window, capped at the period length.
    let window: DateInterval
}

private func precedingPeriods(
    kind: InsightPeriodKind,
    before start: Date,
    elapsedDays: Int,
    count: Int,
    calendar: Calendar
) -> [TrailingPeriod] {
    var periods: [TrailingPeriod] = []
    var cursor = start

    for _ in 0..<count {
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: cursor),
            let interval = calendar.dateInterval(of: kind.component, for: dayBefore)
        else {
            break
        }

        let fullStart = calendar.startOfDay(for: interval.start)
        let fullEnd = calendar.startOfDay(for: interval.end)
        let length = max(1, calendar.dateComponents([.day], from: fullStart, to: fullEnd).day ?? 1)
        let elapsed = min(length, elapsedDays)

        guard let windowEnd = calendar.date(byAdding: .day, value: elapsed, to: fullStart) else {
            break
        }

        periods.append(
            TrailingPeriod(
                full: DateInterval(start: fullStart, end: fullEnd),
                window: DateInterval(start: fullStart, end: windowEnd)
            )
        )
        cursor = fullStart
    }

    return periods
}

// MARK: - Accumulation

private struct CategoryMeta: Equatable, Sendable {
    let name: String
    let symbolName: String
    let colorHex: String
}

private struct PayeeTally: Equatable, Sendable {
    var payee: String
    var count: Int = 0
    var totalMinor: Int64 = 0

    mutating func add(minorUnits: Int64) {
        count += 1
        totalMinor += minorUnits
    }
}

private struct SpendEntry: Equatable, Sendable {
    let minorUnits: Int64
    let payee: String
}

private struct SpendAccumulator {
    var totalMinor: Int64 = 0
    var fixedMinor: Int64 = 0
    var variableMinor: Int64 = 0
    var byCategory: [UUID: Int64] = [:]
    var categoryMeta: [UUID: CategoryMeta] = [:]
    var byDay: [Int: Int64] = [:]
    var byPayee: [String: PayeeTally] = [:]
    var entries: [SpendEntry] = []
    var missingRates: Set<String> = []

    mutating func add(
        minorUnits: Int64,
        categoryID: UUID?,
        meta: CategoryMeta?,
        isFixed: Bool,
        payee: String,
        dayOffset: Int,
        missingCurrency: String?
    ) {
        totalMinor += minorUnits
        byDay[dayOffset, default: 0] += minorUnits

        if isFixed {
            fixedMinor += minorUnits
        } else {
            variableMinor += minorUnits
        }

        if let categoryID, let meta {
            byCategory[categoryID, default: 0] += minorUnits
            categoryMeta[categoryID] = meta
        }

        if !payee.isEmpty {
            byPayee.add(minorUnits: minorUnits, payee: payee)
        }

        entries.append(SpendEntry(minorUnits: minorUnits, payee: payee))

        if let missingCurrency {
            missingRates.insert(missingCurrency)
        }
    }
}

extension Dictionary where Key == String, Value == PayeeTally {
    fileprivate mutating func add(minorUnits: Int64, payee: String) {
        let key = payee.lowercased()

        if var tally = self[key] {
            tally.add(minorUnits: minorUnits)
            // Pick a stable display spelling even when the fetch order changes.
            tally.payee = Swift.min(tally.payee, payee)
            self[key] = tally
        } else {
            var tally = PayeeTally(payee: payee)
            tally.add(minorUnits: minorUnits)
            self[key] = tally
        }
    }
}
