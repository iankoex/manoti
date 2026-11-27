//
//  MovementRulesTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels
@testable import AppServices

@Suite("Movement rules")
struct MovementRulesTests {
    private func message(
        reference: String,
        counterpart: String = "",
        amount: Int64,
        fee: Int64 = 0,
        role: MessageRole = .transaction,
        kind: LedgerEntryKind = .expense,
        date: Date = Date()
    ) -> ParsedMessage {
        ParsedMessage(
            ruleSetName: "Test",
            ruleName: "Test",
            messageType: kind,
            role: role,
            amountMinor: amount,
            currencyCode: "KES",
            feeMinor: fee,
            reference: reference,
            counterpartReference: counterpart,
            occurredAt: date,
            dateFromMessage: true,
            confidence: 1,
            rawText: ""
        )
    }

    @Test("References ignore separators and case")
    func normaliseReference() {
        #expect(MovementRules.normaliseReference(" ukp6-h2tu yy ") == "UKP6H2TUYY")
        #expect(MovementRules.normaliseReference("") == "")
    }

    @Test("A message names its own and its counterpart's reference once each")
    func references() {
        let parsed = message(reference: "UKP6H2R80I", counterpart: "5989CBLR1498", amount: 200_000)
        #expect(MovementRules.references(for: parsed) == ["UKP6H2R80I", "5989CBLR1498"])

        let repeated = message(reference: "UKP6H2R80I", counterpart: "ukp6h2r80i", amount: 1)
        #expect(MovementRules.references(for: repeated) == ["UKP6H2R80I"])
    }

    @Test("Amounts agree on the base or on one side's fee-inclusive total")
    func amounts() {
        #expect(
            MovementRules.amountsAgree(
                minor: 28_000, feeMinor: 500, otherMinor: 28_000, otherFeeMinor: 0
            )
        )
        #expect(
            MovementRules.amountsAgree(
                minor: 27_500, feeMinor: 500, otherMinor: 28_000, otherFeeMinor: 0
            )
        )
        #expect(
            !MovementRules.amountsAgree(
                minor: 28_000, feeMinor: 500, otherMinor: 30_000, otherFeeMinor: 0
            )
        )
        #expect(
            !MovementRules.amountsAgree(
                minor: 0, feeMinor: 0, otherMinor: 28_000, otherFeeMinor: 0
            )
        )
    }

    @Test("An entry matches a message by any of its references")
    func intersection() {
        let entry = LedgerEntry(kind: .expense, amountMinor: 28_000)
        entry.externalRef = "UKP6H2TUYY"

        let parsed = message(reference: "ukp6h2tuyy", amount: 28_000)
        #expect(MovementRules.referencesIntersect(entry: entry, message: parsed))

        let unrelated = message(reference: "OTHER12345", amount: 28_000)
        #expect(!MovementRules.referencesIntersect(entry: entry, message: unrelated))
    }

    @Test("A confirmation only enriches spending and income")
    func confirmationDirection() {
        let expense = LedgerEntry(kind: .expense, amountMinor: 28_000)
        let transfer = LedgerEntry(kind: .transferOut, amountMinor: 28_000)
        let confirmation = message(reference: "UKP6H2TUYY", amount: 28_000, role: .confirmation)

        #expect(MovementRules.directionCompatible(entry: expense, message: confirmation))
        #expect(!MovementRules.directionCompatible(entry: transfer, message: confirmation))
    }

    @Test("A transaction pairs with the opposite transfer leg")
    func transferDirection() {
        let out = LedgerEntry(kind: .transferOut, amountMinor: 200_000)
        let incoming = message(reference: "UKP6H2R80I", amount: 200_000, kind: .transferIn)

        #expect(MovementRules.isOppositeTransferLeg(out, messageType: .transferIn))
        #expect(MovementRules.directionCompatible(entry: out, message: incoming))
    }

    @Test("Old reference matches stay inside the window")
    func window() {
        let now = Date()
        #expect(MovementRules.isWithinWindow(now, now.addingTimeInterval(-3600)))
        #expect(!MovementRules.isWithinWindow(now, now.addingTimeInterval(-49 * 3600)))
    }
}
