//
//  LoanServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("LoanService")
struct LoanServiceTests {
    private struct Services {
        let accounts: AccountService
        let loans: LoanService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return Services(
            accounts: AccountService(context: context),
            loans: LoanService(context: context),
            context: context
        )
    }

    @Test("Lending moves cash out and tracks a receivable")
    func lend() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        #expect(account.balance.minorUnits == 400_000)
        #expect(loan.outstandingMinor == 100_000)
        #expect(loan.entries?.count == 1)
        #expect(loan.entries?.first?.kind == .loanOut)
        #expect(loan.entries?.first?.amountMinor == 100_000)
        #expect(loan.entries?.first?.payee == "Brenda")
        #expect(loan.entries?.first?.account?.id == account.id)
        #expect(loan.currency.code == "KES")
    }

    @Test("Borrowing moves cash in and tracks a payable")
    func borrow() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 50_000)

        let loan = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        #expect(account.balance.minorUnits == 150_000)
        #expect(loan.outstandingMinor == 100_000)
        #expect(loan.entries?.count == 1)
        #expect(loan.entries?.first?.kind == .loanIn)
    }

    @Test("A partial repayment of a borrowed loan reduces cash and outstanding")
    func repayBorrowed() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 50_000)
        let loan = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        let repayment = try services.loans.addRepayment(to: loan, amountMinor: 40_000, account: account)

        #expect(account.balance.minorUnits == 110_000)
        #expect(loan.outstandingMinor == 60_000)
        #expect(repayment.kind == .loanRepaymentOut)
        #expect(repayment.loan?.id == loan.id)
        #expect(loan.status == .open)
    }

    @Test("A partial repayment of a lent loan increases cash and reduces the receivable")
    func repayLent() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        let repayment = try services.loans.addRepayment(to: loan, amountMinor: 40_000, account: account)

        #expect(account.balance.minorUnits == 440_000)
        #expect(loan.outstandingMinor == 60_000)
        #expect(repayment.kind == .loanRepaymentIn)
        #expect(loan.status == .open)
    }

    @Test("A full repayment settles the loan")
    func fullRepaymentSettles() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 50_000)
        let loan = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        try services.loans.addRepayment(to: loan, amountMinor: 100_000, account: account)

        #expect(loan.outstandingMinor == 0)
        #expect(loan.status == .settled)
        #expect(loan.entries?.count == 2)
        #expect(account.balance.minorUnits == 50_000)
    }

    @Test("Settled loans can be excluded from the list")
    func fetchLoansFiltersSettled() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        let settled = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)
        try services.loans.addRepayment(to: settled, amountMinor: 100_000, account: account)

        try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 50_000, account: account)

        let all = try services.loans.fetchLoans()
        let open = try services.loans.fetchLoans(includeSettled: false)

        #expect(all.count == 2)
        #expect(open.count == 1)
        #expect(open.first?.counterparty == "Brenda")
    }

    @Test("An overpayment is rejected and stores nothing")
    func overpaymentRejected() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 50_000)
        let loan = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        #expect(throws: LoanError.overpayment) {
            try services.loans.addRepayment(to: loan, amountMinor: 100_001, account: account)
        }

        #expect(loan.outstandingMinor == 100_000)
        #expect(loan.entries?.count == 1)
        #expect(account.balance.minorUnits == 150_000)
    }

    @Test("Zero and negative amounts are rejected")
    func invalidAmounts() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        #expect(throws: LoanError.invalidAmount) {
            try services.loans.create(
                direction: .lent, counterparty: "Brenda", principalMinor: 0, account: account)
        }
        #expect(throws: LoanError.invalidAmount) {
            try services.loans.create(
                direction: .lent, counterparty: "Brenda", principalMinor: -5, account: account)
        }

        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        #expect(throws: LoanError.invalidAmount) {
            try services.loans.addRepayment(to: loan, amountMinor: 0, account: account)
        }
        #expect(throws: LoanError.invalidAmount) {
            try services.loans.addRepayment(to: loan, amountMinor: -5, account: account)
        }

        #expect(try services.loans.fetchLoans().count == 1)
    }

    @Test("An empty counterparty is rejected")
    func invalidCounterparty() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        #expect(throws: LoanError.invalidCounterparty) {
            try services.loans.create(
                direction: .lent, counterparty: "", principalMinor: 100_000, account: account)
        }
        #expect(throws: LoanError.invalidCounterparty) {
            try services.loans.create(
                direction: .lent, counterparty: "   ", principalMinor: 100_000, account: account)
        }

        #expect(try services.loans.fetchLoans().isEmpty)
    }

    @Test("Archived accounts cannot lend, borrow or repay")
    func archivedAccountRejected() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        try services.accounts.archive(account)

        #expect(throws: LoanError.archivedAccount) {
            try services.loans.create(
                direction: .lent, counterparty: "Brian", principalMinor: 50_000, account: account)
        }
        #expect(throws: LoanError.archivedAccount) {
            try services.loans.addRepayment(to: loan, amountMinor: 10_000, account: account)
        }
    }

    @Test("A repayment account must use the loan currency")
    func currencyMismatchRejected() throws {
        let services = try makeServices()
        let kes = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let usd = try services.accounts.create(
            name: "USD Bank", kind: .bank, currencyCode: "USD", openingBalanceMinor: 100_000)
        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: kes)

        #expect(throws: LoanError.currencyMismatch) {
            try services.loans.addRepayment(to: loan, amountMinor: 10_000, account: usd)
        }

        #expect(loan.entries?.count == 1)
        #expect(loan.outstandingMinor == 100_000)
    }

    @Test("Deleting a loan soft-deletes it and its entries")
    func deleteSoftDeletesLoanAndEntries() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)
        try services.loans.addRepayment(to: loan, amountMinor: 40_000, account: account)

        #expect(account.balance.minorUnits == 440_000)

        try services.loans.delete(loan)

        #expect(loan.isSoftDeleted)
        #expect((loan.entries ?? []).allSatisfy { $0.isSoftDeleted })
        #expect(account.balance.minorUnits == 500_000)
        #expect(try services.loans.fetchLoans().isEmpty)
        #expect(try services.loans.fetchLoans(includeSettled: false).isEmpty)
    }

    @Test("The summary reports receivables and payables separately")
    func summarySeparatesDirections() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)
        try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 50_000, account: account)

        let summary = try services.loans.summary(displayCurrency: .kes)

        #expect(summary.receivable.minorUnits == 100_000)
        #expect(summary.payable.minorUnits == 50_000)
        #expect(summary.missingRates.isEmpty)
    }

    @Test("The summary excludes settled loans")
    func summarySkipsSettled() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let loan = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)
        try services.loans.addRepayment(to: loan, amountMinor: 100_000, account: account)

        let summary = try services.loans.summary(displayCurrency: .kes)

        #expect(summary.receivable.isZero)
        #expect(summary.payable.isZero)
    }

    @Test("The summary ignores future-dated rates")
    func summaryIgnoresFutureRates() throws {
        let services = try makeServices()
        let usd = try services.accounts.create(
            name: "USD Bank", kind: .bank, currencyCode: "USD", openingBalanceMinor: 0)
        try services.loans.create(
            direction: .lent, counterparty: "Alex", principalMinor: 10_000, account: usd)

        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        services.context.insert(
            ExchangeRateRecord(
                baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: yesterday)
        )
        services.context.insert(
            ExchangeRateRecord(
                baseCode: "USD", quoteCode: "KES", rateScaled: 200_000_000, asOf: tomorrow)
        )
        try services.context.save()

        let summary = try services.loans.summary(displayCurrency: .kes)

        #expect(summary.receivable.minorUnits == 1_300_000)
    }

    @Test("A missing rate is reported and converted at major-unit 1:1")
    func summaryMissingRate() throws {
        let services = try makeServices()
        let usd = try services.accounts.create(
            name: "USD Bank", kind: .bank, currencyCode: "USD", openingBalanceMinor: 0)
        try services.loans.create(
            direction: .lent, counterparty: "Alex", principalMinor: 10_000, account: usd)

        let summary = try services.loans.summary(displayCurrency: .kes)

        #expect(summary.receivable.currency.code == "KES")
        // USD 100.00 has no rate, so it becomes KES 100.00 (10,000 minor units).
        #expect(summary.receivable.minorUnits == 10_000)
        #expect(summary.missingRates == ["USD"])
    }
}
