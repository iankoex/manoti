//
//  LedgerServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("LedgerService")
struct LedgerServiceTests {
    private func makeServices() throws -> (AccountService, LedgerService) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (AccountService(context: context), LedgerService(context: context))
    }

    private struct Fixtures {
        let accounts: AccountService
        let ledger: LedgerService
        let context: ModelContext
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return Fixtures(
            accounts: AccountService(context: context),
            ledger: LedgerService(context: context),
            context: context
        )
    }

    private func makeCategory(_ name: String, in context: ModelContext) -> SpendingCategory {
        let group = CategoryGroup(name: "Test group", symbolName: "square.grid.2x2", colorHex: "#FF9500")
        context.insert(group)

        let category = SpendingCategory(name: name, symbolName: "circle", colorHex: "#FF9500")
        category.group = group
        context.insert(category)
        return category
    }

    @Test("Income increases the balance and subtracts its fee")
    func income() throws {
        let (accounts, ledger) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try ledger.record(kind: .income, amountMinor: 100_000, feeMinor: 1_000, account: account)

        #expect(entry.signedAmountMinor == 99_000)
        #expect(account.balance.minorUnits == 99_000)
    }

    @Test("Zero and negative expense amounts are rejected")
    func rejectsNonPositive() throws {
        let (accounts, ledger) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        #expect(throws: LedgerError.nonPositiveAmount) {
            try ledger.record(kind: .expense, amountMinor: 0, account: account)
        }

        #expect(throws: LedgerError.nonPositiveAmount) {
            try ledger.record(kind: .expense, amountMinor: -5, account: account)
        }
    }

    @Test("A manual entry requires an account")
    func manualRequiresAccount() throws {
        let (_, ledger) = try makeServices()

        #expect(throws: LedgerError.missingAccount) {
            try ledger.record(kind: .expense, amountMinor: 100, account: nil)
        }
    }

    @Test("A parsed message with no routed account is stored for review")
    func messageMayLackAccount() throws {
        let (_, ledger) = try makeServices()
        let entry = try ledger.record(kind: .expense, amountMinor: 100, account: nil, source: .message)

        #expect(entry.status == .needsReview)
        #expect(entry.account == nil)
    }

    @Test("Archived accounts cannot receive new entries")
    func archivedRejected() throws {
        let (accounts, ledger) = try makeServices()
        let account = try accounts.create(name: "Old", kind: .bank)
        try accounts.archive(account)

        #expect(throws: LedgerError.archivedAccount) {
            try ledger.record(kind: .expense, amountMinor: 100, account: account)
        }
    }

    @Test("Deleting is a soft delete and can be undone")
    func softDelete() throws {
        let (accounts, ledger) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try ledger.record(kind: .expense, amountMinor: 10_000, account: account)

        try ledger.delete(entry)
        #expect(account.balance.minorUnits == 0)
        #expect(try ledger.recent().isEmpty)

        try ledger.undoDelete(entry)
        #expect(account.balance.minorUnits == -10_000)
        #expect(try ledger.recent().count == 1)
    }

    @Test("Recent entries are newest first")
    func recentOrdering() throws {
        let (accounts, ledger) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let older = try ledger.record(
            kind: .expense,
            amountMinor: 100,
            account: account,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let newer = try ledger.record(
            kind: .expense,
            amountMinor: 200,
            account: account,
            occurredAt: Date(timeIntervalSince1970: 200)
        )

        let entries = try ledger.recent()
        #expect(entries.map(\.id) == [newer.id, older.id])
    }

    @Test("Updating changes editable fields and preserves identity and provenance")
    func updateChangesEditableFields() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let replacement = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let food = makeCategory("Food", in: fixtures.context)
        let transport = makeCategory("Transport", in: fixtures.context)
        transport.kind = .income
        let occurredAt = Date(timeIntervalSince1970: 1_000)
        let createdAt = Date(timeIntervalSince1970: 10)

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            feeMinor: 100,
            account: account,
            category: food,
            payee: "Old payee",
            note: "Old note",
            occurredAt: Date(timeIntervalSince1970: 500)
        )
        entry.createdAt = createdAt
        entry.source = .shortcut
        entry.rawMessage = "raw"
        entry.externalRef = "ref"
        entry.dedupeHash = "hash"
        entry.status = .needsReview
        let id = entry.id

        let updated = try fixtures.ledger.update(
            entry,
            kind: .income,
            amountMinor: 25_000,
            feeMinor: 250,
            account: replacement,
            category: transport,
            payee: "  New payee  ",
            note: "  New note  ",
            occurredAt: occurredAt
        )

        #expect(updated === entry)
        #expect(entry.id == id)
        #expect(entry.kind == .income)
        #expect(entry.amountMinor == 25_000)
        #expect(entry.feeMinor == 250)
        #expect(entry.account?.id == replacement.id)
        #expect(entry.currencyCode == replacement.currencyCode)
        #expect(entry.primaryCategory?.id == transport.id)
        #expect(entry.payee == "New payee")
        #expect(entry.note == "New note")
        #expect(entry.occurredAt == occurredAt)
        #expect(entry.source == .shortcut)
        #expect(entry.rawMessage == "raw")
        #expect(entry.externalRef == "ref")
        #expect(entry.dedupeHash == "hash")
        #expect(entry.status == .needsReview)
        #expect(entry.createdAt == createdAt)
    }

    @Test("Updating rejects zero amounts, negative fees and zero adjustments")
    func updateRejectsNonPositive() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let expense = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: account)
        let occurredAt = expense.occurredAt

        #expect(throws: LedgerError.nonPositiveAmount) {
            try fixtures.ledger.update(
                expense,
                kind: .expense,
                amountMinor: 0,
                feeMinor: 0,
                account: account,
                category: nil,
                payee: "",
                note: "",
                occurredAt: occurredAt
            )
        }

        #expect(throws: LedgerError.nonPositiveAmount) {
            try fixtures.ledger.update(
                expense,
                kind: .expense,
                amountMinor: -5,
                feeMinor: 0,
                account: account,
                category: nil,
                payee: "",
                note: "",
                occurredAt: occurredAt
            )
        }

        #expect(throws: LedgerError.nonPositiveAmount) {
            try fixtures.ledger.update(
                expense,
                kind: .expense,
                amountMinor: 100,
                feeMinor: -1,
                account: account,
                category: nil,
                payee: "",
                note: "",
                occurredAt: occurredAt
            )
        }

        let adjustment = try fixtures.ledger.record(kind: .adjustment, amountMinor: -100, account: account)
        let updated = try fixtures.ledger.update(
            adjustment,
            kind: .adjustment,
            amountMinor: -500,
            feeMinor: 0,
            account: account,
            category: nil,
            payee: "",
            note: "",
            occurredAt: adjustment.occurredAt
        )
        #expect(updated.amountMinor == -500)

        #expect(throws: LedgerError.nonPositiveAmount) {
            try fixtures.ledger.update(
                adjustment,
                kind: .adjustment,
                amountMinor: 0,
                feeMinor: 0,
                account: account,
                category: nil,
                payee: "",
                note: "",
                occurredAt: occurredAt
            )
        }
    }

    @Test("Updating requires a non-archived account")
    func updateRequiresActiveAccount() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let old = try fixtures.accounts.create(name: "Old bank", kind: .bank)
        try fixtures.accounts.archive(old)

        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: account)
        let occurredAt = entry.occurredAt

        #expect(throws: LedgerError.missingAccount) {
            try fixtures.ledger.update(
                entry,
                kind: .expense,
                amountMinor: 10_000,
                feeMinor: 0,
                account: nil,
                category: nil,
                payee: "",
                note: "",
                occurredAt: occurredAt
            )
        }

        #expect(throws: LedgerError.archivedAccount) {
            try fixtures.ledger.update(
                entry,
                kind: .expense,
                amountMinor: 10_000,
                feeMinor: 0,
                account: old,
                category: nil,
                payee: "",
                note: "",
                occurredAt: occurredAt
            )
        }
    }

    @Test("Updating or deleting a linked entry is refused")
    func linkedEntryProtected() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .transferOut, amountMinor: 10_000, account: account)

        let transfer = Transfer()
        fixtures.context.insert(transfer)
        entry.transfer = transfer

        #expect(throws: LedgerError.linkedEntry) {
            try fixtures.ledger.update(
                entry,
                kind: .transferOut,
                amountMinor: 20_000,
                feeMinor: 0,
                account: account,
                category: nil,
                payee: "",
                note: "",
                occurredAt: entry.occurredAt
            )
        }

        #expect(throws: LedgerError.linkedEntry) {
            try fixtures.ledger.delete(entry)
        }
        #expect(entry.isSoftDeleted == false)
    }

    @Test("A deleted entry cannot be updated")
    func updateRejectsDeletedEntry() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: account)
        try fixtures.ledger.delete(entry)

        #expect(throws: LedgerError.alreadyDeleted) {
            try fixtures.ledger.update(
                entry,
                kind: .expense,
                amountMinor: 20_000,
                feeMinor: 0,
                account: account,
                category: nil,
                payee: "",
                note: "",
                occurredAt: entry.occurredAt
            )
        }
    }

    @Test("An entry cannot move to an account in another currency")
    func updateRejectsCurrencyChange() throws {
        let fixtures = try makeFixtures()
        let kes = try fixtures.accounts.create(name: "KES wallet", kind: .mobileMoney)
        let usd = try fixtures.accounts.create(name: "USD bank", kind: .bank, currencyCode: "USD")
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: kes)

        #expect(throws: LedgerError.currencyMismatch(expected: "USD", actual: "KES")) {
            try fixtures.ledger.update(
                entry,
                kind: .expense,
                amountMinor: 2_000,
                feeMinor: 0,
                account: usd,
                category: nil,
                payee: "",
                note: "",
                occurredAt: entry.occurredAt
            )
        }

        #expect(entry.currencyCode == "KES")
        #expect(entry.account?.id == kes.id)
        #expect(entry.amountMinor == 10_000)
    }

    @Test("Moving an entry clears the bank-reported balance")
    func updateClearsBalanceAfter() throws {
        let fixtures = try makeFixtures()
        let first = try fixtures.accounts.create(name: "First", kind: .bank)
        let second = try fixtures.accounts.create(name: "Second", kind: .bank)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: first)
        entry.balanceAfterMinor = 500_000
        try fixtures.context.save()

        try fixtures.ledger.update(
            entry,
            kind: .expense,
            amountMinor: 10_000,
            feeMinor: 0,
            account: second,
            category: nil,
            payee: "",
            note: "",
            occurredAt: entry.occurredAt
        )

        #expect(entry.account?.id == second.id)
        #expect(entry.balanceAfterMinor == nil)
    }
}
