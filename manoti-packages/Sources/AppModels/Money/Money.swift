//
//  Money.swift
//  AppModels
//

import Foundation

nonisolated public enum MoneyError: Error, Equatable {
    case currencyMismatch(expected: String, actual: String)
    case invalidAmount
}

/// An exact amount in a currency's minor units. Never backed by `Double`.
nonisolated public struct Money: Hashable, Sendable, Codable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Converts a decimal major-unit amount, rounding half-even at the minor-unit boundary.
    public init?(decimal: Decimal, currency: Currency) {
        guard !decimal.isNaN else {
            return nil
        }

        let scaled = decimal * Self.powerOfTen(currency.exponent)
        guard !scaled.isNaN else {
            return nil
        }

        let number = NSDecimalNumber(decimal: scaled)
        let rounded = number.rounding(accordingToBehavior: Self.bankersHandler)

        guard rounded != .notANumber else {
            return nil
        }

        guard rounded.compare(Self.maximumDecimal) != .orderedDescending,
            rounded.compare(Self.minimumDecimal) != .orderedAscending
        else {
            return nil
        }

        self.init(minorUnits: rounded.int64Value, currency: currency)
    }

    public var decimalValue: Decimal {
        Decimal(minorUnits) / Self.powerOfTen(currency.exponent)
    }

    public var isZero: Bool {
        minorUnits == 0
    }

    /// The unsigned size of the amount, safe for `Int64.min`.
    public var magnitude: UInt64 {
        minorUnits.magnitude
    }

    /// The same amount with the opposite sign, or nil when that would overflow.
    public var negated: Money? {
        guard minorUnits != .min else {
            return nil
        }

        return Money(minorUnits: -minorUnits, currency: currency)
    }

    public func formatted(locale: Locale = .current) -> String {
        "\(currency.code) \(formattedDecimal(decimalValue, locale: locale))"
    }

    /// Formats the unsigned size of the amount. Used for signed display without
    /// constructing `-Int64.min`.
    public func formattedMagnitude(locale: Locale = .current) -> String {
        "\(currency.code) \(formattedDecimal(decimalValue.magnitude, locale: locale))"
    }

    /// Adds two amounts, refusing to mix currencies.
    public func adding(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(expected: currency.code, actual: other.currency.code)
        }

        let (sum, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else {
            throw MoneyError.invalidAmount
        }

        return Money(minorUnits: sum, currency: currency)
    }

    /// Subtracts two amounts, refusing to mix currencies.
    public func subtracting(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(expected: currency.code, actual: other.currency.code)
        }

        let (difference, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else {
            throw MoneyError.invalidAmount
        }

        return Money(minorUnits: difference, currency: currency)
    }

    public static func zero(in currency: Currency) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    private func formattedDecimal(_ value: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = currency.exponent
        formatter.maximumFractionDigits = currency.exponent

        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    static func powerOfTen(_ exponent: Int) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }

    private static let maximumDecimal = NSDecimalNumber(value: Int64.max)
    private static let minimumDecimal = NSDecimalNumber(value: Int64.min)

    static var bankersHandler: NSDecimalNumberHandler {
        NSDecimalNumberHandler(
            roundingMode: .bankers,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
    }
}
