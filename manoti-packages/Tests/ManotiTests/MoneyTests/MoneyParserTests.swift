//
//  MoneyParserTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("MoneyParser")
struct MoneyParserTests {
    private let kes = CurrencyCatalog.currency(for: "KES")

    @Test("Parses M-Pesa and bank amount shapes")
    func bankShapes() throws {
        let cases: [(String, Int64)] = [
            ("Ksh1,510.00", 151_000),
            ("KES 5000", 500_000),
            ("KES 16,700.00", 1_670_000),
            ("Ksh100.00", 10_000),
            ("KSHS 45.5", 4_550),
            ("KES5000", 500_000),
        ]

        for (text, expected) in cases {
            let parsed = try #require(MoneyParser.parse(text, defaultCurrency: kes), "\(text)")
            #expect(parsed.money.minorUnits == expected, "\(text)")
            #expect(parsed.money.currency.code == "KES", "\(text)")
            #expect(parsed.hadCurrencyToken, "\(text)")
        }
    }

    @Test("A bare number parses but reports no currency token")
    func bareNumber() throws {
        let parsed = try #require(MoneyParser.parse("1,234.50", defaultCurrency: kes))
        #expect(parsed.money.minorUnits == 123_450)
        #expect(parsed.hadCurrencyToken == false)
    }

    @Test("A trailing comma with two digits is a decimal separator")
    func commaDecimal() throws {
        let parsed = try #require(MoneyParser.parse("Ksh100,50", defaultCurrency: kes))
        #expect(parsed.money.minorUnits == 10_050)
    }

    @Test("A comma group of three digits is a thousands separator")
    func thousandsSeparator() throws {
        let parsed = try #require(MoneyParser.parse("Ksh1,250", defaultCurrency: kes))
        #expect(parsed.money.minorUnits == 125_000)
    }

    @Test("Dollar and euro prefixes map to their currencies")
    func symbols() throws {
        #expect(try #require(MoneyParser.parse("$12.34", defaultCurrency: kes)).money.currency.code == "USD")
        #expect(try #require(MoneyParser.parse("€9,99", defaultCurrency: kes)).money.minorUnits == 999)
    }

    @Test("Text without a number fails")
    func noNumber() {
        #expect(MoneyParser.parse("Confirmed.", defaultCurrency: kes) == nil)
        #expect(MoneyParser.parse("", defaultCurrency: kes) == nil)
        #expect(MoneyParser.parse("abc", defaultCurrency: kes) == nil)
    }

    @Test("Negative amounts keep their sign")
    func negativeAmounts() throws {
        #expect(try #require(MoneyParser.parse("-2,000", defaultCurrency: kes)).money.minorUnits == -200_000)
        #expect(try #require(MoneyParser.parse("(500)", defaultCurrency: kes)).money.minorUnits == -50_000)
        #expect(try #require(MoneyParser.parse("−1,510.00", defaultCurrency: kes)).money.minorUnits == -151_000)
    }

    @Test("Grouped amounts survive internal spaces")
    func spacedGrouping() throws {
        #expect(try #require(MoneyParser.parse("1 000", defaultCurrency: kes)).money.minorUnits == 100_000)
        #expect(
            try #require(MoneyParser.parse("KES 1\u{00A0}234,50", defaultCurrency: kes)).money.minorUnits
                == 123_450
        )
        #expect(
            try #require(MoneyParser.parse("KES 1\u{202F}234", defaultCurrency: kes)).money.minorUnits
                == 123_400
        )
    }

    @Test("Dot thousands are not read as decimals")
    func dotThousands() throws {
        #expect(try #require(MoneyParser.parse("€1.234", defaultCurrency: kes)).money.minorUnits == 123_400)
        #expect(try #require(MoneyParser.parse("KES 1.510", defaultCurrency: kes)).money.minorUnits == 151_000)
        #expect(try #require(MoneyParser.parse("12.345,67", defaultCurrency: kes)).money.minorUnits == 1_234_567)
        #expect(MoneyParser.parse("1.234.56", defaultCurrency: kes) == nil)
    }

    @Test("A suffix currency token selects the currency")
    func suffixToken() throws {
        let usd = CurrencyCatalog.currency(for: "USD")
        let parsed = try #require(MoneyParser.parse("130,000 KES", defaultCurrency: usd))

        #expect(parsed.money.currency.code == "KES")
        #expect(parsed.money.minorUnits == 13_000_000)
        #expect(parsed.hadCurrencyToken)
    }

    @Test("A spelled currency with a period still parses")
    func spelledCurrency() throws {
        let parsed = try #require(MoneyParser.parse("Kshs. 500", defaultCurrency: kes))

        #expect(parsed.money.minorUnits == 50_000)
        #expect(parsed.money.currency.code == "KES")
        #expect(parsed.hadCurrencyToken)
    }
}
