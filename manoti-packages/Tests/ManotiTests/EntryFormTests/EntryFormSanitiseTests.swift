//
//  EntryFormSanitiseTests.swift
//  ManotiTests
//

import Testing

@testable import EntryFormFeature

@Suite("Entry form amount sanitising")
struct EntryFormSanitiseTests {
    @Test("Letters and spaces from a hardware keyboard are dropped")
    func lettersDropped() {
        #expect(EntryFormState.sanitisedAmountText("500 w 1", exponent: 2) == "5001")
    }

    @Test("Only the first decimal separator counts and the fraction is capped")
    func fractionCapped() {
        #expect(EntryFormState.sanitisedAmountText("12.345", exponent: 2) == "12.34")
        #expect(EntryFormState.sanitisedAmountText("1.2.3", exponent: 2) == "1.23")
    }

    @Test("A leading separator becomes zero point")
    func leadingSeparator() {
        #expect(EntryFormState.sanitisedAmountText(".5", exponent: 2) == "0.5")
        #expect(EntryFormState.sanitisedAmountText(",5", exponent: 2) == "0.5")
    }

    @Test("A minus is kept only where the field allows it")
    func negativeAllowed() {
        #expect(EntryFormState.sanitisedAmountText("-250", exponent: 2, allowsNegative: true) == "-250")
        #expect(EntryFormState.sanitisedAmountText("-250", exponent: 2, allowsNegative: false) == "250")
    }

    @Test("Zero-decimal currencies ignore separators")
    func zeroExponent() {
        #expect(EntryFormState.sanitisedAmountText("12.5", exponent: 0) == "125")
    }
}
