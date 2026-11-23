//
//  BalanceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels

@MainActor
@Suite("Account balance")
struct BalanceTests {
    private func makeAccount(in context: ModelContext) -> Account {
        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(account)
        return account
    }

    @Test("Opening balance is one ledger row and is never added twice")
    func openingBalanceIsOneRow() {
        let container = try? ModelContainerFactory.make(inMemory: true)
        guard let container else {
            Issue.record("Could not build an in-memory container")
            return
        }

        let context = ModelContext(container)
        let account = makeAccount(in: context)

        let opening = LedgerEntry(kind: .openingBalance, amountMinor: 500_000)
        opening.account = account
        context.insert(opening)

        #expect(AccountBalance.balanceMinor(for: account) == 500_000)
        #expect(account.transactions?.count == 1)
    }

    @Test("An expense subtracts its amount and its fee")
    func expenseWithFee() {
        let container = try? ModelContainerFactory.make(inMemory: true)
        guard let container else {
            Issue.record("Could not build an in-memory container")
            return
        }

        let context = ModelContext(container)
        let account = makeAccount(in: context)

        let opening = LedgerEntry(kind: .openingBalance, amountMinor: 500_000)
        opening.account = account
        context.insert(opening)

        let expense = LedgerEntry(kind: .expense, amountMinor: 151_000, feeMinor: 830)
        expense.account = account
        context.insert(expense)

        #expect(expense.signedAmountMinor == -151_830)
        #expect(AccountBalance.balanceMinor(for: account) == 348_170)
        #expect(account.balance.minorUnits == 348_170)
    }

    @Test("Fee-only and income signs are correct")
    func incomeSigns() {
        let income = LedgerEntry(kind: .income, amountMinor: 100_000)
        #expect(income.signedAmountMinor == 100_000)

        let incomeWithFee = LedgerEntry(kind: .income, amountMinor: 100_000, feeMinor: 1_000)
        #expect(incomeWithFee.signedAmountMinor == 99_000)

        let adjustment = LedgerEntry(kind: .adjustment, amountMinor: -25_000)
        #expect(adjustment.signedAmountMinor == -25_000)
    }

    @Test("Soft-deleted rows stop affecting the balance")
    func softDelete() {
        let container = try? ModelContainerFactory.make(inMemory: true)
        guard let container else {
            Issue.record("Could not build an in-memory container")
            return
        }

        let context = ModelContext(container)
        let account = makeAccount(in: context)

        let expense = LedgerEntry(kind: .expense, amountMinor: 10_000)
        expense.account = account
        context.insert(expense)

        #expect(AccountBalance.balanceMinor(for: account) == -10_000)

        expense.isSoftDeleted = true
        #expect(AccountBalance.balanceMinor(for: account) == 0)
        #expect(account.transactions?.count == 1)
    }

    @Test("Ignored rows stop affecting the balance")
    func ignoredRow() {
        let container = try? ModelContainerFactory.make(inMemory: true)
        guard let container else {
            Issue.record("Could not build an in-memory container")
            return
        }

        let context = ModelContext(container)
        let account = makeAccount(in: context)

        let opening = LedgerEntry(kind: .openingBalance, amountMinor: 500_000)
        opening.account = account
        context.insert(opening)

        let expense = LedgerEntry(kind: .expense, amountMinor: 10_000)
        expense.account = account
        context.insert(expense)

        #expect(AccountBalance.balanceMinor(for: account) == 490_000)

        expense.status = .ignored

        #expect(AccountBalance.balanceMinor(for: account) == 500_000)
    }

    @Test("A transfer pair nets to the fee across both accounts")
    func transferPair() {
        let container = try? ModelContainerFactory.make(inMemory: true)
        guard let container else {
            Issue.record("Could not build an in-memory container")
            return
        }

        let context = ModelContext(container)

        let bank = Account(name: "IM Bank", kind: .bank)
        let mobile = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(bank)
        context.insert(mobile)

        let transfer = Transfer()
        let out = LedgerEntry(kind: .transferOut, amountMinor: 100_000, feeMinor: 2_500)
        out.account = bank
        out.transfer = transfer

        let inbound = LedgerEntry(kind: .transferIn, amountMinor: 100_000)
        inbound.account = mobile
        inbound.transfer = transfer

        context.insert(transfer)
        context.insert(out)
        context.insert(inbound)

        #expect(AccountBalance.balanceMinor(for: bank) == -102_500)
        #expect(AccountBalance.balanceMinor(for: mobile) == 100_000)
        #expect(transfer.outTransaction?.id == out.id)
        #expect(transfer.inTransaction?.id == inbound.id)
        #expect(transfer.fee?.minorUnits == 2_500)
        #expect(transfer.rate?.convert(Money(minorUnits: 100_000, currency: Currency.kes))?.minorUnits == 100_000)
    }
}
