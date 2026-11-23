//
//  AccountServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("AccountService")
struct AccountServiceTests {
    private func makeServices() throws -> (AccountService, LedgerService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (AccountService(context: context), LedgerService(context: context), context)
    }

    @Test("Creating an account writes one opening-balance row")
    func createWithOpeningBalance() throws {
        let (accounts, _, _) = try makeServices()

        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        #expect(account.balance.minorUnits == 500_000)
        #expect(account.transactions?.count == 1)
        #expect(account.transactions?.first?.kind == .openingBalance)
    }

    @Test("An expense reduces the balance by amount plus fee")
    func expenseReducesBalance() throws {
        let (accounts, ledger, _) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        try ledger.record(kind: .expense, amountMinor: 151_000, feeMinor: 830, account: account)

        #expect(account.balance.minorUnits == 348_170)
    }

    @Test("Account details can be renamed and restyled")
    func updateDetails() throws {
        let (accounts, _, _) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        try accounts.updateDetails(
            account,
            name: "  Mobile money  ",
            kind: .bank,
            colorHex: "#123456",
            symbolName: "building.columns",
            institution: "  Bank  "
        )

        #expect(account.name == "Mobile money")
        #expect(account.kind == .bank)
        #expect(account.colorHex == "123456")
        #expect(account.institution == "Bank")
    }

    @Test("Editing an opening balance shifts the balance by the delta")
    func editOpeningBalance() throws {
        let (accounts, ledger, _) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)
        try ledger.record(kind: .expense, amountMinor: 200_000, account: account)

        try accounts.updateOpeningBalance(account, to: 600_000)

        #expect(account.balance.minorUnits == 400_000)
        #expect(account.transactions?.filter { $0.kind == .openingBalance }.count == 1)
    }

    @Test("An opening balance cannot move once an earlier row exists")
    func openingBalanceLocked() throws {
        let (accounts, ledger, _) = try makeServices()
        let account = try accounts.create(
            name: "M-Pesa",
            kind: .mobileMoney,
            openingBalanceMinor: 500_000,
            openedAt: Date(timeIntervalSince1970: 1_000)
        )

        try ledger.record(
            kind: .expense,
            amountMinor: 1_000,
            account: account,
            occurredAt: Date(timeIntervalSince1970: 500)
        )

        #expect(throws: AccountError.openingBalanceLocked) {
            try accounts.updateOpeningBalance(account, to: 1)
        }
    }

    @Test("Duplicate names are rejected case-insensitively")
    func duplicateName() throws {
        let (accounts, _, _) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        #expect(throws: AccountError.duplicateName) {
            try accounts.create(name: "m-pesa", kind: .mobileMoney)
        }
    }

    @Test("Routing prefers card last-4 over account number and ignores archived accounts")
    func routing() throws {
        let (accounts, _, _) = try makeServices()

        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: bank)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: mobile)

        #expect(accounts.account(forIdentifier: "5477********7653")?.id == mobile.id)
        #expect(accounts.account(forIdentifier: "Acc 01234567890123")?.id == bank.id)

        let prefixOnly = try accounts.create(name: "Other card", kind: .card)
        try accounts.addIdentifier(value: "5477", type: .cardLast4, to: prefixOnly)
        #expect(accounts.account(forIdentifier: "5477********7653")?.id == mobile.id)

        try accounts.archive(mobile)

        #expect(accounts.account(forIdentifier: "5477********7653") == nil)
        #expect(try accounts.fetchAccounts().count == 2)
        #expect(try accounts.fetchAccounts(includeArchived: true).count == 3)
    }
}
