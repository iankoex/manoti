//
//  MoneyTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("Money")
struct MoneyTests {
    private let kes = Currency(code: "KES", exponent: 2)
    private let ugx = Currency(code: "UGX", exponent: 0)

    @Test("Decimal converts to minor units at the currency exponent")
    func decimalToMinorUnits() throws {
        let value = try #require(Decimal(string: "1510.00"))
        let money = try #require(Money(decimal: value, currency: kes))
        #expect(money.minorUnits == 151_000)
    }

    @Test("A zero-exponent currency has no minor units")
    func zeroExponent() throws {
        let money = try #require(Money(decimal: 5_000, currency: ugx))
        #expect(money.minorUnits == 5_000)
        #expect(money.decimalValue == 5_000)
    }

    @Test("Amounts add and subtract only within one currency")
    func arithmetic() throws {
        let a = Money(minorUnits: 151_000, currency: kes)
        let b = Money(minorUnits: 830, currency: kes)

        #expect(try a.adding(b).minorUnits == 151_830)
        #expect(try a.subtracting(b).minorUnits == 150_170)
        #expect(try #require(a.negated).minorUnits == -151_000)
    }

    @Test("Mismatched currencies throw instead of silently summing")
    func mismatchedCurrencies() {
        let a = Money(minorUnits: 100, currency: kes)
        let b = Money(minorUnits: 100, currency: ugx)

        #expect(throws: MoneyError.currencyMismatch(expected: "KES", actual: "UGX")) {
            try a.adding(b)
        }
        #expect(throws: MoneyError.currencyMismatch(expected: "KES", actual: "UGX")) {
            try a.subtracting(b)
        }
    }

    @Test("Overflow is reported instead of trapping")
    func overflow() {
        let maximum = Money(minorUnits: .max, currency: kes)
        let minimum = Money(minorUnits: .min, currency: kes)
        let one = Money(minorUnits: 1, currency: kes)

        #expect(throws: MoneyError.invalidAmount) { try maximum.adding(one) }
        #expect(throws: MoneyError.invalidAmount) { try minimum.subtracting(one) }
        #expect(minimum.magnitude == UInt64(Int64.max) + 1)
        #expect(minimum.negated == nil)
    }

    @Test("Decimal conversion rejects values outside the Int64 range")
    func outOfRangeDecimal() {
        let huge = Decimal(sign: .plus, exponent: 30, significand: 1)
        #expect(Money(decimal: huge, currency: kes) == nil)
        #expect(Money(decimal: Decimal.nan, currency: kes) == nil)
    }

    @Test("Formatting honours the currency exponent and code")
    func formatting() {
        let locale = Locale(identifier: "en_KE")
        let formatted = Money(minorUnits: 151_000, currency: kes).formatted(locale: locale)

        #expect(formatted.contains("1,510.00"))
        #expect(formatted.contains("KES"))

        let noCents = Money(minorUnits: 2_850, currency: ugx).formatted(locale: locale)
        #expect(noCents.contains("2,850"))
        #expect(noCents.contains("UGX"))
    }

    @Test("Rounding uses bankers rounding at the minor-unit boundary")
    func rounding() throws {
        let halfValue = try #require(Decimal(string: "0.005"))
        let half = try #require(Money(decimal: halfValue, currency: kes))
        #expect(half.minorUnits == 0)

        let upValue = try #require(Decimal(string: "0.015"))
        let up = try #require(Money(decimal: upValue, currency: kes))
        #expect(up.minorUnits == 2)
    }
}

@Suite("CurrencyCatalog")
struct CurrencyCatalogTests {
    @Test("Known codes win, unknown codes default to two decimals")
    func lookup() {
        #expect(CurrencyCatalog.currency(for: "KES").exponent == 2)
        #expect(CurrencyCatalog.currency(for: "UGX").exponent == 0)
        #expect(CurrencyCatalog.currency(for: "JPY").exponent == 0)
        #expect(CurrencyCatalog.currency(for: "xyz").exponent == 2)
        #expect(CurrencyCatalog.currency(for: "xyz").code == "XYZ")
    }

    @Test("Three-decimal currencies keep their exponent")
    func threeDecimalCurrencies() {
        for code in ["KWD", "BHD", "OMR", "TND", "JOD", "LYD", "IQD"] {
            #expect(CurrencyCatalog.isKnown(code), "\(code)")
            #expect(CurrencyCatalog.currency(for: code).exponent == 3, "\(code)")
        }
    }

    @Test("Unknown codes are distinguishable from supported ones")
    func knownCodes() {
        #expect(CurrencyCatalog.isKnown("kes"))
        #expect(!CurrencyCatalog.isKnown("XYZ"))
    }

    @Test("The default currency is Kenyan shillings")
    func defaultCurrency() {
        #expect(CurrencyCatalog.defaultCurrency.code == "KES")
        #expect(CurrencyCatalog.supported.contains(CurrencyCatalog.defaultCurrency))
    }
}
