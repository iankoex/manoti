//
//  AmountEntryTests.swift
//  ManotiTests
//

import Testing

@testable import AppModels

@Suite("Amount entry")
struct AmountEntryTests {
    @Test("Digits build a major-unit string and one decimal point is allowed")
    func digits() {
        var text = ""

        for key in ["1", "2", "3", ".", "4", "5"] {
            AmountEntry.apply(key, to: &text)
        }

        #expect(text == "123.45")

        AmountEntry.apply(".", to: &text)
        #expect(text == "123.45")
    }

    @Test("Only two decimals are accepted and delete removes one character")
    func limits() {
        var text = "12.34"
        AmountEntry.apply("5", to: &text)
        #expect(text == "12.34")

        AmountEntry.apply("⌫", to: &text)
        #expect(text == "12.3")
    }

    @Test("A leading zero is replaced by the first digit")
    func leadingZero() {
        var text = "0"
        AmountEntry.apply("7", to: &text)
        #expect(text == "7")
    }

    @Test("A three-decimal currency accepts a third decimal")
    func threeDecimals() {
        var text = ""
        for key in ["1", "2", ".", "3", "4", "5"] {
            AmountEntry.apply(key, to: &text, exponent: 3)
        }

        #expect(text == "12.345")

        AmountEntry.apply("6", to: &text, exponent: 3)
        #expect(text == "12.345")
    }

    @Test("A zero-decimal currency refuses a decimal point")
    func zeroDecimals() {
        var text = "12"
        AmountEntry.apply(".", to: &text, exponent: 0)
        #expect(text == "12")

        AmountEntry.apply("5", to: &text, exponent: 0)
        #expect(text == "125")
    }
}
