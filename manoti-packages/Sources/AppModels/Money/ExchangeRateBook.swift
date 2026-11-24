//
//  ExchangeRateBook.swift
//  AppModels
//

import Foundation

/// The known rates for each currency pair, resolved from stored records.
///
/// Lookups are date-aware: a conversion uses the newest rate that was effective on the
/// conversion date, so adding a later rate never rewrites an earlier transaction. Both
/// directions of a pair are considered, and the newer record wins even when it was stored
/// as the inverse of the requested pair.
nonisolated public struct ExchangeRateBook: Sendable {
    private struct DatedRate: Sendable {
        let asOf: Date
        let createdAt: Date
        let id: UUID
        let rate: FXRate
    }

    private let history: [String: [DatedRate]]
    private let calendar: Calendar

    public init(records: [ExchangeRateRecord], calendar: Calendar = .current) {
        self.calendar = calendar

        let sorted = records.sorted { lhs, rhs in
            if lhs.asOf != rhs.asOf {
                return lhs.asOf < rhs.asOf
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }

        var history: [String: [DatedRate]] = [:]

        for record in sorted {
            guard let rate = record.rate else {
                continue
            }

            let key = Self.key(rate.base.code, rate.quote.code)
            history[key, default: []].append(
                DatedRate(
                    asOf: record.asOf,
                    createdAt: record.createdAt,
                    id: record.id,
                    rate: rate
                )
            )
        }

        self.history = history
    }

    /// The newest rate for a pair, regardless of date. Use for current values such as net worth.
    public func rate(from base: Currency, to quote: Currency) -> FXRate? {
        guard base != quote else {
            return FXRate(base: base, quote: quote, rateScaled: FXRate.scale)
        }

        return newestRate(
            newest(in: history[Self.key(base.code, quote.code)] ?? []),
            inverse: newest(in: history[Self.key(quote.code, base.code)] ?? [])
        )
    }

    /// The rate that was effective on `date`. A date before the first stored rate has no rate.
    ///
    /// Comparison is by calendar day so a rate captured later in the day (for example at
    /// 14:00) still applies to an entry made earlier the same morning.
    public func rate(from base: Currency, to quote: Currency, on date: Date) -> FXRate? {
        guard base != quote else {
            return FXRate(base: base, quote: quote, rateScaled: FXRate.scale)
        }

        return newestRate(
            rate(forKey: Self.key(base.code, quote.code), on: date),
            inverse: rate(forKey: Self.key(quote.code, base.code), on: date)
        )
    }

    public func convert(_ money: Money, to currency: Currency) -> Money? {
        if money.currency == currency {
            return money
        }

        return rate(from: money.currency, to: currency)?.convert(money)
    }

    public func convert(_ money: Money, to currency: Currency, on date: Date) -> Money? {
        if money.currency == currency {
            return money
        }

        return rate(from: money.currency, to: currency, on: date)?.convert(money)
    }

    /// Picks the newer of the two directions. The direct record is preferred only when the
    /// records are identical on date, creation time and identifier (which cannot happen for
    /// two distinct records, but keeps the result total and predictable).
    private func newestRate(_ direct: DatedRate?, inverse: DatedRate?) -> FXRate? {
        switch (direct, inverse) {
            case (let direct?, let inverse?):
                return isNewer(direct, than: inverse) ? direct.rate : inverse.rate.inverted
            case (let direct?, nil):
                return direct.rate
            case (nil, let inverse?):
                return inverse.rate.inverted
            case (nil, nil):
                return nil
        }
    }

    private func isNewer(_ lhs: DatedRate, than rhs: DatedRate) -> Bool {
        let lhsDay = calendar.startOfDay(for: lhs.asOf)
        let rhsDay = calendar.startOfDay(for: rhs.asOf)

        if lhsDay != rhsDay {
            return lhsDay > rhsDay
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString >= rhs.id.uuidString
    }

    private func rate(forKey key: String, on date: Date) -> DatedRate? {
        guard let rates = history[key] else {
            return nil
        }

        let day = calendar.startOfDay(for: date)
        let candidates = rates.filter { calendar.startOfDay(for: $0.asOf) <= day }
        return newest(in: candidates)
    }

    /// Selects by the same order used across directions, not by array position: effective
    /// day first, then creation time, then id. This keeps a manual correction entered later
    /// today ahead of a transfer rate captured earlier today.
    private func newest(in rates: [DatedRate]) -> DatedRate? {
        var best: DatedRate?

        for rate in rates {
            if let current = best {
                if isNewer(rate, than: current) {
                    best = rate
                }
            } else {
                best = rate
            }
        }

        return best
    }

    private static func key(_ base: String, _ quote: String) -> String {
        "\(base.uppercased())>\(quote.uppercased())"
    }
}
