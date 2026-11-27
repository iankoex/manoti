//
//  SplitTemplateLearningTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import EntryFormFeature

@MainActor
@Suite("Split template learning")
struct SplitTemplateLearningTests {
    private struct Fixtures {
        let ledger: LedgerService
        let accounts: AccountService
        let categoriser: CategoriserService
        let account: Account
        let household: SpendingCategory
        let groceries: SpendingCategory
        let context: ModelContext
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let accounts = AccountService(context: context)
        let account = try accounts.create(name: "Card", kind: .card)

        func makeCategory(_ name: String) -> SpendingCategory {
            let category = SpendingCategory(name: name, symbolName: "circle", colorHex: "#FF9500")
            context.insert(category)
            return category
        }

        let household = makeCategory("Household")
        let groceries = makeCategory("Groceries")
        try context.save()

        return Fixtures(
            ledger: LedgerService(context: context),
            accounts: accounts,
            categoriser: CategoriserService(context: context),
            account: account,
            household: household,
            groceries: groceries,
            context: context
        )
    }

    private func recordSplit(_ fixtures: Fixtures, payee: String = "Supermarket") throws -> LedgerEntry {
        try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: fixtures.account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: fixtures.household),
                LedgerLineInput(amountMinor: 20_000, category: fixtures.groceries),
            ],
            payee: payee
        )
    }

    @Test("A manual split teaches the merchant's proportions")
    func learnsSplit() throws {
        let fixtures = try makeFixtures()
        _ = try recordSplit(fixtures)

        let template = try #require(try fixtures.categoriser.splitTemplate(for: "Supermarket"))

        #expect(template.lines.map(\.categoryID) == [fixtures.household.id, fixtures.groceries.id])
        #expect(template.lines.map(\.weightBasisPoints) == [6_000, 4_000])
    }

    @Test("A single-category entry teaches no split")
    func singleLineTeachesNoSplit() throws {
        let fixtures = try makeFixtures()
        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: fixtures.account,
            lines: [LedgerLineInput(amountMinor: 10_000, category: fixtures.groceries)],
            payee: "Cafe"
        )

        #expect(try fixtures.categoriser.splitTemplate(for: "Cafe") == nil)
    }

    @Test("Ingested entries do not teach a split")
    func ingestDoesNotTeach() throws {
        let fixtures = try makeFixtures()
        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: fixtures.account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: fixtures.household),
                LedgerLineInput(amountMinor: 20_000, category: fixtures.groceries),
            ],
            payee: "Supermarket",
            source: .message
        )

        #expect(try fixtures.categoriser.splitTemplate(for: "Supermarket") == nil)
    }

    @Test("Applying a template fills lines with the same proportions")
    func appliesTemplate() throws {
        let fixtures = try makeFixtures()
        _ = try recordSplit(fixtures)
        let template = try #require(try fixtures.categoriser.splitTemplate(for: "Supermarket"))

        let state = EntryFormState(
            accounts: [fixtures.account],
            categories: [fixtures.household, fixtures.groceries]
        )
        state.amountText = "1000"
        state.selectedAccountID = fixtures.account.id

        state.applySplitTemplate(template)

        #expect(state.isSplit)
        #expect(state.lineDrafts?.count == 2)
        #expect(state.lineDrafts?.map(\.amountText) == ["600", "400"])
        #expect(
            state.lineDrafts?.map(\.categoryID)
                == [fixtures.household.id, fixtures.groceries.id]
        )
        #expect(state.linesTotalMinor == 100_000)
    }

    @Test("A template survives a backup and restore")
    func backupRoundTrip() throws {
        let fixtures = try makeFixtures()
        _ = try recordSplit(fixtures)
        let data = try ExportService(context: fixtures.context).backupData()

        let target = ModelContext(try ModelContainerFactory.make(inMemory: true))
        _ = try ExportService(context: target).restore(data: data)

        let memory = try #require(try target.fetch(FetchDescriptor<MerchantMemory>()).first)
        let template = try #require(memory.splitTemplate)

        #expect(template.lines.map(\.categoryID) == [fixtures.household.id, fixtures.groceries.id])
        #expect(template.lines.map(\.weightBasisPoints) == [6_000, 4_000])
    }
}
