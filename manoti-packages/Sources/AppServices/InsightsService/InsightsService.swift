//
//  InsightsService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

/// A period total in the display currency, plus any currencies that had no rate and were
/// therefore shown 1:1 in major units.
nonisolated public struct PeriodTotal: Equatable, Sendable {
    public let amount: Money
    public let missingRates: [String]

    public init(amount: Money, missingRates: [String]) {
        self.amount = amount
        self.missingRates = missingRates
    }
}

nonisolated public struct DailySpend: Identifiable, Sendable {
    public let date: Date
    public let total: Money
    public let missingRates: [String]

    public var id: Date { date }

    public init(date: Date, total: Money, missingRates: [String] = []) {
        self.date = date
        self.total = total
        self.missingRates = missingRates
    }
}

/// Net worth, period totals, daily spending and equal-elapsed period comparisons.
///
/// `context` is internal so the comparison maths can live in its own extension file while
/// still reading the same store.
@Observable
nonisolated public final class InsightsService: Loggable {
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func rateBook() throws -> ExchangeRateBook {
        let records = try context.fetch(
            FetchDescriptor<ExchangeRateRecord>(sortBy: [SortDescriptor(\ExchangeRateRecord.asOf, order: .reverse)])
        )
        return ExchangeRateBook(records: records)
    }

    /// Personal reports ignore company money. Entries without an account (still in review)
    /// count as personal but are excluded by status anyway.
    func includes(_ entry: LedgerEntry, in scope: AccountOwnershipScope) -> Bool {
        scope == .all || entry.account?.isCompany != true
    }

    public func total(
        kind: LedgerEntryKind,
        from start: Date,
        to end: Date,
        displayCurrency: Currency,
        ownership: AccountOwnershipScope = .personal
    ) throws -> PeriodTotal {
        let book = try rateBook()
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.statusRaw == "confirmed" && $0.occurredAt >= start
                    && $0.occurredAt < end
            }
        )

        let entries = try context.fetch(descriptor)
        var total: Int64 = 0
        var missing: Set<String> = []

        for entry in entries
        where entry.kind == kind && entry.transfer == nil && entry.loan == nil
            && entry.investmentCashFlow == nil && includes(entry, in: ownership)
        {
            let amount = Money(minorUnits: abs(entry.signedAmountMinor), currency: entry.currency)

            if let converted = book.convert(amount, to: displayCurrency, on: entry.occurredAt) {
                total += converted.minorUnits
            } else {
                missing.insert(entry.currency.code)
                total += fallback(amount, to: displayCurrency).minorUnits
            }
        }

        return PeriodTotal(
            amount: Money(minorUnits: total, currency: displayCurrency),
            missingRates: missing.sorted()
        )
    }

    /// Spending per calendar day for the trailing `days`, including today, in display currency.
    public func dailySpend(
        days: Int,
        displayCurrency: Currency,
        calendar: Calendar = .current,
        now: Date = Date(),
        ownership: AccountOwnershipScope = .personal
    ) throws -> [DailySpend] {
        let bucketCount = max(1, days)
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(bucketCount - 1), to: startOfToday) else {
            return []
        }

        let book = try rateBook()
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.kindRaw == "expense" && $0.statusRaw == "confirmed"
                    && $0.occurredAt >= start && $0.occurredAt <= now
            }
        )

        var buckets: [Date: Int64] = [:]
        var missingByDay: [Date: Set<String>] = [:]

        for entry in try context.fetch(descriptor)
        where entry.transfer == nil && entry.loan == nil && entry.investmentCashFlow == nil
            && includes(entry, in: ownership)
        {
            let amount = Money(minorUnits: abs(entry.signedAmountMinor), currency: entry.currency)
            let day = calendar.startOfDay(for: entry.occurredAt)

            if let converted = book.convert(amount, to: displayCurrency, on: entry.occurredAt) {
                buckets[day, default: 0] += converted.minorUnits
            } else {
                missingByDay[day, default: []].insert(entry.currency.code)
                buckets[day, default: 0] += fallback(amount, to: displayCurrency).minorUnits
            }
        }

        return (0..<bucketCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }

            return DailySpend(
                date: day,
                total: Money(minorUnits: buckets[day] ?? 0, currency: displayCurrency),
                missingRates: (missingByDay[day] ?? []).sorted()
            )
        }
    }

    /// Reinterprets the major-unit amount in the display currency. Used only when no rate is
    /// available, so the caller can show the amount 1:1 without rescaling by exponent.
    func fallback(_ money: Money, to currency: Currency) -> Money {
        Money(decimal: money.decimalValue, currency: currency) ?? .zero(in: currency)
    }
}
