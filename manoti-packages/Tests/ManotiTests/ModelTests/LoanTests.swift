//
//  LoanTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels

@MainActor
@Suite("Loan")
struct LoanTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    @Test("A lent loan's outstanding falls as repayments come in")
    func lentOutstanding() throws {
        let context = try makeContext()
        let loan = Loan(direction: .lent, counterparty: "Brenda", principalMinor: 100_000, currencyCode: "KES")
        context.insert(loan)

        let disbursement = LedgerEntry(kind: .loanOut, amountMinor: 100_000)
        disbursement.loan = loan
        context.insert(disbursement)

        let repayment = LedgerEntry(kind: .loanRepaymentIn, amountMinor: 40_000)
        repayment.loan = loan
        context.insert(repayment)

        #expect(LoanBalance.outstandingMinor(for: loan) == 60_000)
        #expect(loan.outstandingMinor == 60_000)
        #expect(loan.outstanding.minorUnits == 60_000)
        #expect(loan.outstanding.currency.code == "KES")
    }

    @Test("A borrowed loan's outstanding falls as repayments go out")
    func borrowedOutstanding() throws {
        let context = try makeContext()
        let loan = Loan(direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, currencyCode: "KES")
        context.insert(loan)

        let disbursement = LedgerEntry(kind: .loanIn, amountMinor: 100_000)
        disbursement.loan = loan
        context.insert(disbursement)

        let repayment = LedgerEntry(kind: .loanRepaymentOut, amountMinor: 40_000)
        repayment.loan = loan
        context.insert(repayment)

        #expect(LoanBalance.outstandingMinor(for: loan) == 60_000)
        #expect(loan.outstandingMinor == 60_000)
    }

    @Test("Soft-deleted repayments do not reduce outstanding")
    func softDeletedRepaymentIgnored() throws {
        let context = try makeContext()
        let loan = Loan(direction: .lent, counterparty: "Brenda", principalMinor: 100_000, currencyCode: "KES")
        context.insert(loan)

        let repayment = LedgerEntry(kind: .loanRepaymentIn, amountMinor: 40_000)
        repayment.loan = loan
        repayment.isSoftDeleted = true
        context.insert(repayment)

        #expect(LoanBalance.outstandingMinor(for: loan) == 100_000)
    }

    @Test("Outstanding never goes below zero")
    func outstandingClampsAtZero() throws {
        let context = try makeContext()
        let loan = Loan(direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, currencyCode: "KES")
        context.insert(loan)

        let repayment = LedgerEntry(kind: .loanRepaymentOut, amountMinor: 120_000)
        repayment.loan = loan
        context.insert(repayment)

        #expect(LoanBalance.outstandingMinor(for: loan) == 0)
    }

    @Test("Loan ledger kinds sign the account balance correctly")
    func loanEntrySigns() {
        let out = LedgerEntry(kind: .loanOut, amountMinor: 100_000, feeMinor: 500)
        #expect(out.signedAmountMinor == -100_500)

        let inbound = LedgerEntry(kind: .loanIn, amountMinor: 100_000, feeMinor: 500)
        #expect(inbound.signedAmountMinor == 99_500)

        let repaymentOut = LedgerEntry(kind: .loanRepaymentOut, amountMinor: 40_000, feeMinor: 200)
        #expect(repaymentOut.signedAmountMinor == -40_200)

        let repaymentIn = LedgerEntry(kind: .loanRepaymentIn, amountMinor: 40_000, feeMinor: 200)
        #expect(repaymentIn.signedAmountMinor == 39_800)
    }

    @Test("Loan kinds are neither spending nor income")
    func loanKindsAreNotSpendingOrIncome() {
        for kind in [LedgerEntryKind.loanOut, .loanIn, .loanRepaymentOut, .loanRepaymentIn] {
            #expect(!kind.countsAsSpending)
            #expect(!kind.countsAsIncome)
            #expect(!kind.isTransferLeg)
        }
    }

    @Test("The schema stores Loan")
    func schemaContainsLoan() {
        #expect(ManotiSchema.models.count == 26)
        #expect(ManotiSchema.models.contains { $0 == Loan.self })
    }

    @Test("Loan kinds carry display names and symbols")
    func kindMetadata() {
        #expect(LedgerEntryKind.loanOut.displayName == "Loan given")
        #expect(LedgerEntryKind.loanIn.displayName == "Loan received")
        #expect(LedgerEntryKind.loanRepaymentOut.displayName == "Loan repayment")
        #expect(LedgerEntryKind.loanRepaymentIn.displayName == "Repayment received")
        #expect(LedgerEntryKind.loanOut.symbolName == "arrow.up.right")
        #expect(LedgerEntryKind.loanIn.symbolName == "arrow.down.left")
    }
}
