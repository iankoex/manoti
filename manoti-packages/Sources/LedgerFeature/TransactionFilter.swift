//
//  TransactionFilter.swift
//  LedgerFeature
//

import AppModels
import Foundation

public enum TransactionDatePreset: String, CaseIterable, Identifiable, Sendable {
    case any
    case today
    case yesterday
    case last7
    case last30
    case thisMonth
    case lastMonth
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
            case .any: "Any time"
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .last7: "Last 7 days"
            case .last30: "Last 30 days"
            case .thisMonth: "This month"
            case .lastMonth: "Last month"
            case .custom: "Custom"
        }
    }
}

public enum TransactionDateMode: String, CaseIterable, Identifiable, Sendable {
    case between
    case before
    case after

    public var id: String { rawValue }

    public var title: String {
        switch self {
            case .between: "Between"
            case .before: "Before"
            case .after: "After"
        }
    }
}

/// Everything the Transactions screen can narrow down except the free-text search.
public struct TransactionFilter: Equatable, Sendable {
    /// Every type is on by default, so an untouched filter shows everything.
    public var accountKinds: Set<AccountKind> = Set(AccountKind.allCases)
    public var accountIDs: Set<UUID> = []
    public var minimumAmountText = ""
    public var maximumAmountText = ""
    public var datePreset: TransactionDatePreset = .any
    public var dateMode: TransactionDateMode = .between
    public var customFrom: Date
    public var customTo: Date

    public init() {
        let calendar = Calendar.current
        customFrom = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        customTo = .now
    }

    public var isActive: Bool {
        accountKinds != Set(AccountKind.allCases)
            || !accountIDs.isEmpty
            || !minimumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !maximumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || datePreset != .any
    }

    public mutating func reset() {
        self = TransactionFilter()
    }
}

public enum TransactionFilterEngine {
    /// Filters in memory. A personal ledger is small enough that this keeps search and
    /// custom ranges exact, without predicate limits or missing pages.
    public static func apply(
        _ entries: [LedgerEntry],
        filter: TransactionFilter,
        searchText: String,
        displayCurrency: Currency,
        rateBook: ExchangeRateBook?,
        now: Date,
        calendar: Calendar
    ) -> [LedgerEntry] {
        let range = dateRange(filter: filter, now: now, calendar: calendar)
        let bounds = amountBounds(filter: filter, currency: displayCurrency)
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return entries.filter { entry in
            if let range {
                guard entry.occurredAt >= range.start, entry.occurredAt < range.end else {
                    return false
                }
            }

            // Types are on by default. Turning one off excludes it; entries without a
            // type are excluded too once the type filter is narrowed.
            if filter.accountKinds != Set(AccountKind.allCases) {
                guard let kind = entry.account?.kind, filter.accountKinds.contains(kind) else {
                    return false
                }
            }

            if !filter.accountIDs.isEmpty {
                guard let id = entry.account?.id, filter.accountIDs.contains(id) else {
                    return false
                }
            }

            if let bounds {
                let money = Money(minorUnits: entry.amountMinor, currency: entry.currency)
                // Missing rates fall back to 1:1, the same convention the summaries use.
                let converted =
                    rateBook?.convert(money, to: displayCurrency, on: entry.occurredAt)
                    ?? Money(minorUnits: entry.amountMinor, currency: displayCurrency)

                guard bounds.contains(converted.minorUnits) else {
                    return false
                }
            }

            if !search.isEmpty {
                let fields = [
                    entry.payee,
                    entry.note,
                    entry.category?.name ?? "",
                    entry.account?.displayName ?? "",
                ]

                guard fields.contains(where: { $0.localizedStandardContains(search) }) else {
                    return false
                }
            }

            return true
        }
    }

    static func dateRange(
        filter: TransactionFilter,
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        let dayAfterToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        switch filter.datePreset {
            case .any:
                return nil

            case .today:
                return (today, dayAfterToday)

            case .yesterday:
                let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
                return (start, today)

            case .last7:
                let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
                return (start, dayAfterToday)

            case .last30:
                let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
                return (start, dayAfterToday)

            case .thisMonth:
                if let interval = calendar.dateInterval(of: .month, for: now) {
                    return (interval.start, interval.end)
                }

                return (today, dayAfterToday)

            case .lastMonth:
                let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
                if let interval = calendar.dateInterval(of: .month, for: previous) {
                    return (interval.start, interval.end)
                }

                return (today, dayAfterToday)

            case .custom:
                let from = calendar.startOfDay(for: filter.customFrom)
                let to = calendar.startOfDay(for: filter.customTo)

                switch filter.dateMode {
                    case .between:
                        let start = min(from, to)
                        let end = max(from, to)
                        return (start, calendar.date(byAdding: .day, value: 1, to: end) ?? end)

                    case .before:
                        return (Date.distantPast, from)

                    case .after:
                        let start = calendar.date(byAdding: .day, value: 1, to: from) ?? from
                        return (start, Date.distantFuture)
                }
        }
    }

    static func amountBounds(
        filter: TransactionFilter,
        currency: Currency
    ) -> ClosedRange<Int64>? {
        let minimum = minorUnits(from: filter.minimumAmountText, currency: currency)
        let maximum = minorUnits(from: filter.maximumAmountText, currency: currency)

        switch (minimum, maximum) {
            case (nil, nil):
                return nil
            case (let value?, nil):
                return value...Int64.max
            case (nil, let value?):
                return Int64.min...value
            case (let first?, let second?):
                return min(first, second)...max(first, second)
        }
    }

    private static func minorUnits(from text: String, currency: Currency) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return MoneyParser.parse(trimmed, defaultCurrency: currency)?.money.minorUnits
    }
}
