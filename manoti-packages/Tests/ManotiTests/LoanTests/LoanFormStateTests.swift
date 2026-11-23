//
//  LoanFormStateTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import LoansFeature

@MainActor
@Suite("Loan forms")
struct LoanFormStateTests {
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

    @Test("An empty form cannot be saved")
    func emptyFormCannotSave() throws {
        let state = LoanFormState()

        #expect(state.canSave == false)

        state.counterparty = "Brenda"
        state.amountText = "1,000"
        #expect(state.canSave == false)
    }

    @Test("A zero or unparseable amount cannot be saved")
    func invalidAmountCannotSave() throws {
        let services = try makeServices()
        _ = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        let state = LoanFormState()
        state.reload(accountService: services.accounts)
        state.counterparty = "Brenda"

        state.amountText = "0"
        #expect(state.canSave == false)

        state.amountText = "not money"
        #expect(state.canSave == false)
    }

    @Test("A valid lend saves with the selected account and a trimmed counterparty")
    func saveLendTrimsCounterparty() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        let state = LoanFormState(direction: .lent)
        state.reload(accountService: services.accounts)
        state.counterparty = "  Brenda  "
        state.amountText = "1,000"

        #expect(state.canSave)
        #expect(state.selectedAccount?.id == account.id)

        let loan = try state.save(loanService: services.loans)

        #expect(loan.direction == .lent)
        #expect(loan.counterparty == "Brenda")
        #expect(loan.principalMinor == 100_000)
        #expect(loan.currency.code == "KES")
        #expect(loan.entries?.count == 1)
        #expect(loan.entries?.first?.kind == .loanOut)
        #expect(loan.entries?.first?.account?.id == account.id)
        #expect(account.balance.minorUnits == 400_000)
    }

    @Test("Archived accounts are excluded from the picker")
    func archivedAccountsAreExcluded() throws {
        let services = try makeServices()
        let active = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let archived = try services.accounts.create(
            name: "Old Bank", kind: .bank, openingBalanceMinor: 100_000)
        try services.accounts.archive(archived)

        let state = LoanFormState()
        state.reload(accountService: services.accounts)
        state.counterparty = "Brenda"
        state.amountText = "500"

        #expect(state.activeAccounts.map(\.id) == [active.id])
        #expect(state.selectedAccount?.id == active.id)
        #expect(state.canSave)
    }

    @Test("A repayment cannot exceed the outstanding balance")
    func repaymentRejectsOverpayment() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let loan = try services.loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        let state = RepaymentFormState(loan: loan)
        state.reload(accountService: services.accounts)
        state.amountText = "1,000.01"

        #expect(state.canSave == false)
        #expect(state.validationMessage?.contains("cannot exceed") == true)

        #expect(throws: LoanError.overpayment) {
            try state.save(loanService: services.loans)
        }

        #expect(loan.outstandingMinor == 100_000)
        #expect(loan.entries?.count == 1)
    }

    @Test("A repayment previews the remaining balance")
    func repaymentPreviewsRemaining() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        let loan = try services.loans.create(
            direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        let state = RepaymentFormState(loan: loan)
        state.reload(accountService: services.accounts)
        state.amountText = "400"

        #expect(state.canSave)
        #expect(state.remainingPreview?.minorUnits == 60_000)
        #expect(state.selectedAccount?.id == account.id)

        try state.save(loanService: services.loans)

        #expect(loan.outstandingMinor == 60_000)
        #expect(account.balance.minorUnits == 440_000)
    }
}
