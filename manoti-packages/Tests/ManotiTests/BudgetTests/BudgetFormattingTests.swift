//
//  BudgetFormattingTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels
@testable import BudgetFeature

@Suite("Budget formatting")
struct BudgetFormattingTests {
    @Test("Progress fractions clamp an overspent envelope to one")
    func progressFractions() {
        #expect(BudgetFormatting.progressFraction(spentMinor: 25, limitMinor: 100) == 0.25)
        #expect(BudgetFormatting.progressFraction(spentMinor: 150, limitMinor: 100) == 1)
        #expect(BudgetFormatting.progressFraction(spentMinor: 50, limitMinor: 0) == 0)
        #expect(BudgetFormatting.progressFraction(spentMinor: -50, limitMinor: 100) == 0)
    }

    @Test("Percent used keeps overspend and hides a zero limit")
    func percentUsed() {
        #expect(BudgetFormatting.percentUsed(spentMinor: 60, limitMinor: 100) == 60)
        #expect(BudgetFormatting.percentUsed(spentMinor: 120, limitMinor: 100) == 120)
        #expect(BudgetFormatting.percentUsed(spentMinor: 50, limitMinor: 0) == nil)
    }

    @Test("Pacing is the elapsed share of the period")
    func pacingFraction() {
        #expect(BudgetFormatting.pacingFraction(totalDays: 30, elapsedDays: 15) == 0.5)
        #expect(BudgetFormatting.pacingFraction(totalDays: 30, elapsedDays: 0) == 0)
        #expect(BudgetFormatting.pacingFraction(totalDays: 0, elapsedDays: 5) == 0)
        #expect(BudgetFormatting.pacingFraction(totalDays: 30, elapsedDays: 45) == 1)
    }

    @Test("Limits prefill as plain editable text without grouping")
    func limitText() {
        #expect(BudgetFormatting.limitText(for: Money(minorUnits: 123_450, currency: .kes)) == "1234.5")
        #expect(BudgetFormatting.limitText(for: Money(minorUnits: 0, currency: .kes)) == "0")
    }

    @Test("The envelope count uses a singular form for one envelope")
    func envelopeCount() {
        #expect(BudgetFormatting.envelopeCount(1, kind: .month) == "1 envelope · month")
        #expect(BudgetFormatting.envelopeCount(0, kind: .month) == "0 envelopes · month")
        #expect(BudgetFormatting.envelopeCount(3, kind: .week) == "3 envelopes · week")
    }
}
