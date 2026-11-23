//
//  FXRate.swift
//  AppModels
//

import Foundation

/// A conversion rate expressed as *quote major units per 1 base major unit*, scaled by
/// `FXRate.scale`. Storing the major-unit rate is what keeps currencies with different
/// exponents (KES 2, UGX 0, JPY 0) from being off by a factor of 100.
nonisolated public struct FXRate: Hashable, Sendable {
    public static let scale: Int64 = 1_000_000

    public let base: Currency
    public let quote: Currency
    public let rateScaled: Int64

    public init?(base: Currency, quote: Currency, rateScaled: Int64) {
        guard rateScaled > 0 else {
            return nil
        }

        self.base = base
        self.quote = quote
        self.rateScaled = rateScaled
    }

    public init?(base: Currency, quote: Currency, decimalRate: Decimal) {
        guard !decimalRate.isNaN, decimalRate > 0 else {
            return nil
        }

        let scaled = decimalRate * Decimal(Self.scale)
        let rounded = NSDecimalNumber(decimal: scaled).rounding(accordingToBehavior: Money.bankersHandler)

        guard rounded.int64Value > 0 else {
            return nil
        }

        self.init(base: base, quote: quote, rateScaled: rounded.int64Value)
    }

    /// Converts a base-currency amount, or returns `nil` when the amount is in another currency.
    public func convert(_ money: Money) -> Money? {
        guard money.currency == base else {
            return nil
        }

        let numerator = Decimal(money.minorUnits) * Decimal(rateScaled) * Money.powerOfTen(quote.exponent)
        let denominator = Decimal(Self.scale) * Money.powerOfTen(base.exponent)
        let value = numerator / denominator
        let rounded = NSDecimalNumber(decimal: value).rounding(accordingToBehavior: Money.bankersHandler)

        return Money(minorUnits: rounded.int64Value, currency: quote)
    }

    public var inverted: FXRate {
        let square = Decimal(Self.scale) * Decimal(Self.scale)
        let value = square / Decimal(rateScaled)
        let rounded = max(
            1, NSDecimalNumber(decimal: value).rounding(accordingToBehavior: Money.bankersHandler).int64Value)

        return FXRate(base: quote, quote: base, uncheckedRateScaled: rounded)
    }

    private init(base: Currency, quote: Currency, uncheckedRateScaled: Int64) {
        self.base = base
        self.quote = quote
        self.rateScaled = uncheckedRateScaled
    }
}
