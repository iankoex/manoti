//
//  LedgerLineTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Ledger lines")
struct LedgerLineTests {
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

    private func makeCategory(
        _ name: String,
        kind: CategoryKind = .expense,
        in context: ModelContext
    ) -> SpendingCategory {
        let category = SpendingCategory(name: name, symbolName: "circle", colorHex: "#FF9500", kind: kind)
        context.insert(category)
        return category
    }

    @Test("Two lines carry their own categories and add up to the entry")
    func splitSavesTwoLines() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)
        let supplies = makeCategory("Supplies", in: fixtures.context)
        let groceries = makeCategory("Groceries", in: fixtures.context)

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: supplies),
                LedgerLineInput(amountMinor: 20_000, category: groceries),
            ]
        )

        #expect(entry.orderedLines.count == 2)
        #expect(entry.orderedLines.map(\.amountMinor) == [30_000, 20_000])
        #expect(entry.orderedLines.map { $0.category?.name } == ["Supplies", "Groceries"])
        #expect(entry.signedAmountMinor == -50_000)
    }

    @Test("Lines that do not add up to the entry are rejected")
    func mismatchIsRejected() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)
        let groceries = makeCategory("Groceries", in: fixtures.context)

        #expect(throws: LedgerError.linesDoNotMatchTotal(expectedMinor: 50_000, actualMinor: 40_000)) {
            try fixtures.ledger.record(
                kind: .expense,
                amountMinor: 50_000,
                account: account,
                lines: [LedgerLineInput(amountMinor: 40_000, category: groceries)]
            )
        }
    }

    @Test("An expense without lines is rejected")
    func emptyLinesAreRejected() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)

        #expect(throws: LedgerError.linesRequired) {
            try fixtures.ledger.record(kind: .expense, amountMinor: 50_000, account: account, lines: [])
        }
    }

    @Test("A zero-amount line is rejected")
    func zeroLineIsRejected() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)

        #expect(throws: LedgerError.lineAmountInvalid) {
            try fixtures.ledger.record(
                kind: .expense,
                amountMinor: 50_000,
                account: account,
                lines: [LedgerLineInput(amountMinor: 0)]
            )
        }
    }

    @Test("A line category must match the entry kind")
    func categoryKindMustMatch() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)
        let salary = makeCategory("Salary", kind: .income, in: fixtures.context)

        #expect(throws: LedgerError.lineCategoryMismatch) {
            try fixtures.ledger.record(
                kind: .expense,
                amountMinor: 50_000,
                account: account,
                lines: [LedgerLineInput(amountMinor: 50_000, category: salary)]
            )
        }
    }

    @Test("A transfer cannot carry lines")
    func transferCannotCarryLines() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let groceries = makeCategory("Groceries", in: fixtures.context)

        #expect(throws: LedgerError.linesNotAllowed) {
            try fixtures.ledger.record(
                kind: .transferOut,
                amountMinor: 10_000,
                account: account,
                lines: [LedgerLineInput(amountMinor: 10_000, category: groceries)]
            )
        }
    }

    @Test("Updating replaces the lines and keeps the account balance")
    func updateReplacesLines() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)
        let groceries = makeCategory("Groceries", in: fixtures.context)
        let supplies = makeCategory("Supplies", in: fixtures.context)
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 50_000, category: groceries)]
        )
        let oldLineIDs = Set(entry.orderedLines.map(\.id))

        try fixtures.ledger.update(
            entry,
            kind: .expense,
            amountMinor: 50_000,
            feeMinor: 0,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 10_000, category: groceries),
                LedgerLineInput(amountMinor: 40_000, category: supplies),
            ],
            payee: "",
            note: "",
            occurredAt: entry.occurredAt
        )

        #expect(entry.orderedLines.count == 2)
        #expect(entry.orderedLines.map(\.amountMinor) == [10_000, 40_000])
        #expect(Set(entry.orderedLines.map(\.id)).isDisjoint(with: oldLineIDs))
        #expect(account.balance.minorUnits == -50_000)
    }

    @Test("A line-less expense is repaired once and then left alone")
    func repairIsIdempotent() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let entry = LedgerEntry(kind: .expense, amountMinor: 70_000, currencyCode: "KES")
        entry.account = account
        fixtures.context.insert(entry)
        try fixtures.context.save()

        let pipeline = MaintenancePipeline(context: fixtures.context)
        #expect(pipeline.repairEntryLines() == 1)
        #expect(entry.orderedLines.map(\.amountMinor) == [70_000])
        #expect(entry.orderedLines.first?.category == nil)

        #expect(pipeline.repairEntryLines() == 0)
        #expect(entry.orderedLines.count == 1)
    }

    @Test("Repair leaves transfers and entries that already have lines untouched")
    func repairSkipsOtherKinds() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let expiry = LedgerEntry(kind: .transferOut, amountMinor: 10_000, currencyCode: "KES")
        expiry.account = account
        fixtures.context.insert(expiry)

        let repairedEntry = try fixtures.ledger.record(
            kind: .income,
            amountMinor: 20_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 20_000)]
        )

        let pipeline = MaintenancePipeline(context: fixtures.context)
        #expect(pipeline.repairEntryLines() == 0)
        #expect(expiry.orderedLines.isEmpty)
        #expect(repairedEntry.orderedLines.count == 1)
    }
}
