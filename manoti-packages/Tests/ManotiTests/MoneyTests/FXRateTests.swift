//
//  FXRateTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("FXRate")
struct FXRateTests {
    private let kes = CurrencyCatalog.currency(for: "KES")
    private let ugx = CurrencyCatalog.currency(for: "UGX")
    private let jpy = CurrencyCatalog.currency(for: "JPY")
    private let usd = CurrencyCatalog.currency(for: "USD")

    @Test("KES to UGX respects the zero-exponent shilling")
    func kesToUgx() throws {
        let rate = try #require(FXRate(base: kes, quote: ugx, decimalRate: 28.5))
        let converted = try #require(rate.convert(Money(minorUnits: 10_000, currency: kes)))

        #expect(converted.currency.code == "UGX")
        #expect(converted.minorUnits == 2_850)
    }

    @Test("KES to JPY respects the zero-exponent yen")
    func kesToJpy() throws {
        let rate = try #require(FXRate(base: kes, quote: jpy, decimalRate: 0.55))
        let converted = try #require(rate.convert(Money(minorUnits: 100_000, currency: kes)))

        #expect(converted.minorUnits == 550)
    }

    @Test("KES to USD keeps both exponents")
    func kesToUsd() throws {
        let rate = try #require(FXRate(base: kes, quote: usd, decimalRate: 0.00775))
        let converted = try #require(rate.convert(Money(minorUnits: 1_000_000, currency: kes)))

        #expect(converted.minorUnits == 7_750)
    }

    @Test("Converting the wrong base currency fails")
    func wrongBase() throws {
        let rate = try #require(FXRate(base: kes, quote: ugx, decimalRate: 28.5))
        #expect(rate.convert(Money(minorUnits: 100, currency: usd)) == nil)
    }

    @Test("An inverted rate round-trips within rounding")
    func inversion() throws {
        let rate = try #require(FXRate(base: kes, quote: usd, decimalRate: 0.00775))
        let back = try #require(rate.inverted.convert(Money(minorUnits: 7_750, currency: usd)))

        #expect(back.currency.code == "KES")
        #expect(abs(back.minorUnits - 1_000_000) <= 1)
    }

    @Test("A non-positive rate is rejected")
    func rejectsNonPositive() {
        #expect(FXRate(base: kes, quote: usd, decimalRate: 0) == nil)
        #expect(FXRate(base: kes, quote: usd, decimalRate: -1) == nil)
        #expect(FXRate(base: kes, quote: usd, rateScaled: 0) == nil)
    }
}
