//
//  EntryFormSplitTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import EntryFormFeature

@MainActor
@Suite("Entry form splitting")
struct EntryFormSplitTests {
    private struct Fixtures {
        let accounts: AccountService
        let ledger: LedgerService
        let tags: TagService
        let account: Account
        let groceries: SpendingCategory
        let supplies: SpendingCategory
        let salary: SpendingCategory
        let tag: AppModels.Tag
        let context: ModelContext
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let accounts = AccountService(context: context)
        let account = try accounts.create(name: "Card", kind: .card)

        func makeCategory(_ name: String, kind: CategoryKind = .expense) -> SpendingCategory {
            let category = SpendingCategory(
                name: name, symbolName: "circle", colorHex: "#FF9500", kind: kind)
            context.insert(category)
            return category
        }

        let tags = TagService(context: context)
        let tag = try tags.createTag(name: "Nakuru")
        try context.save()

        return Fixtures(
            accounts: accounts,
            ledger: LedgerService(context: context),
            tags: tags,
            account: account,
            groceries: makeCategory("Groceries"),
            supplies: makeCategory("Household"),
            salary: makeCategory("Salary", kind: .income),
            tag: tag,
            context: context
        )
    }

    private func makeState(_ fixtures: Fixtures, purpose: EntryFormState.Purpose = .create) -> EntryFormState {
        EntryFormState(
            purpose: purpose,
            accounts: [fixtures.account],
            categories: [fixtures.groceries, fixtures.supplies, fixtures.salary],
            tags: [fixtures.tag]
        )
    }

    @Test("A one-line entry saves its category and tag")
    func singleLineSaves() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.selectedCategoryID = fixtures.groceries.id
        state.toggleTag(fixtures.tag.id)

        let entry = try state.save(ledger: fixtures.ledger)

        #expect(entry.orderedLines.count == 1)
        #expect(entry.orderedLines.first?.amountMinor == 50_000)
        #expect(entry.orderedLines.first?.category?.id == fixtures.groceries.id)
        #expect(entry.orderedLines.first?.tagList.map(\.id) == [fixtures.tag.id])
    }

    @Test("A split entry saves each line with its own category")
    func splitSavesLines() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.selectedCategoryID = fixtures.groceries.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "300"

        state.addLine()
        state.lineDrafts?[1].amountText = "200"
        state.lineDrafts?[1].categoryID = fixtures.supplies.id

        let entry = try state.save(ledger: fixtures.ledger)

        #expect(entry.orderedLines.count == 2)
        #expect(entry.orderedLines.map(\.amountMinor) == [30_000, 20_000])
        #expect(entry.orderedLines.map { $0.category?.name } == ["Groceries", "Household"])
    }

    @Test("Lines that do not add up block saving and say by how much")
    func mismatchBlocksSave() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.selectedCategoryID = fixtures.groceries.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "400"

        #expect(!state.canSave)
        #expect(state.splitValidationMessage?.contains("500") == true)
    }

    @Test("A zero line blocks saving")
    func zeroLineBlocksSave() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "500"
        state.addLine()

        #expect(!state.canSave)
        #expect(state.splitValidationMessage != nil)
    }

    @Test("Adding a line leaves it blank and does not pre-fill the remainder")
    func addLineIsBlank() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "300"

        let id = try #require(state.addLine())

        #expect(state.lineDrafts?.last?.id == id)
        #expect(state.lineDrafts?.last?.amountText == "")
        #expect(state.lineDrafts?.count == 2)
        #expect(state.splitRemainderMinor == 20_000)
    }

    @Test("The remainder button adds a new line with what is left")
    func remainderAddsLine() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "300"

        let id = try #require(state.addRemainderLine())

        #expect(state.lineDrafts?.count == 2)
        #expect(state.lineDrafts?.last?.id == id)
        #expect(state.lineDrafts?.last?.amountText == "200")
        #expect(state.linesTotalMinor == 50_000)
        #expect(state.splitRemainderMinor == 0)
        #expect(state.splitValidationMessage == nil)
    }

    @Test("The remainder fills an empty last line instead of adding another")
    func remainderFillsBlankLine() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "300"
        let blankID = try #require(state.addLine())

        let id = try #require(state.addRemainderLine())

        #expect(id == blankID)
        #expect(state.lineDrafts?.count == 2)
        #expect(state.lineDrafts?.last?.amountText == "200")
        #expect(state.linesTotalMinor == 50_000)
    }

    @Test("Review mode can split the entry")
    func reviewCanSplit() throws {
        let fixtures = try makeFixtures()
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: fixtures.account,
            lines: [LedgerLineInput(amountMinor: 50_000, category: fixtures.groceries)]
        )

        let state = EntryFormState(
            purpose: .review,
            entry: entry,
            accounts: [fixtures.account],
            categories: [fixtures.groceries, fixtures.supplies],
            tags: [fixtures.tag]
        )

        state.beginSplit()
        #expect(state.isSplit)

        state.lineDrafts?[0].amountText = "300"
        state.lineDrafts?[0].categoryID = fixtures.groceries.id
        state.addLine()
        state.lineDrafts?[1].amountText = "200"
        state.lineDrafts?[1].categoryID = fixtures.supplies.id

        let saved = try state.save(ledger: fixtures.ledger)
        #expect(saved.orderedLines.map(\.amountMinor) == [30_000, 20_000])
        #expect(saved.orderedLines.map { $0.category?.name } == ["Groceries", "Household"])

        // Confirming the review must not flatten the split back onto one line.
        try InboxService(context: fixtures.context).confirm(
            saved,
            account: fixtures.account,
            category: fixtures.groceries
        )

        #expect(saved.orderedLines.count == 2)
        #expect(saved.orderedLines.map { $0.category?.name } == ["Groceries", "Household"])
    }

    @Test("A line with the wrong category kind blocks saving")
    func wrongCategoryKind() throws {
        let fixtures = try makeFixtures()
        let state = makeState(fixtures)

        state.amountText = "500"
        state.selectedAccountID = fixtures.account.id
        state.beginSplit()
        state.lineDrafts?[0].amountText = "500"
        state.lineDrafts?[0].categoryID = fixtures.salary.id

        #expect(!state.canSave)
        #expect(state.splitValidationMessage != nil)
    }

    @Test("Review mode keeps one line and saves its tag")
    func reviewSavesTag() throws {
        let fixtures = try makeFixtures()
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: fixtures.account,
            lines: [LedgerLineInput(amountMinor: 10_000, category: fixtures.groceries)]
        )

        let state = EntryFormState(
            purpose: .review,
            entry: entry,
            accounts: [fixtures.account],
            categories: [fixtures.groceries, fixtures.supplies],
            tags: [fixtures.tag]
        )

        #expect(!state.isSplit)
        state.toggleTag(fixtures.tag.id)

        let saved = try state.save(ledger: fixtures.ledger)
        #expect(saved.orderedLines.count == 1)
        #expect(saved.orderedLines.first?.tagList.map(\.id) == [fixtures.tag.id])
    }

    @Test("Editing keeps a closed tag that is no longer offered")
    func closedTagPreservedOnEdit() throws {
        let fixtures = try makeFixtures()
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: fixtures.account,
            lines: [LedgerLineInput(amountMinor: 10_000, category: fixtures.groceries, tags: [fixtures.tag])]
        )
        try fixtures.tags.closeTag(fixtures.tag)

        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [fixtures.account],
            categories: [fixtures.groceries, fixtures.supplies]
        )
        state.reload(
            accountService: fixtures.accounts,
            categoryService: CategoryService(context: fixtures.context),
            tagService: fixtures.tags
        )

        let saved = try state.save(ledger: fixtures.ledger)
        #expect(saved.orderedLines.first?.tagList.map(\.id) == [fixtures.tag.id])
    }

    @Test("An archived category on a later line survives an edit")
    func archivedLaterCategorySurvives() throws {
        let fixtures = try makeFixtures()
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: fixtures.account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: fixtures.groceries),
                LedgerLineInput(amountMinor: 20_000, category: fixtures.supplies),
            ]
        )
        fixtures.supplies.isArchived = true
        try fixtures.context.save()

        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [fixtures.account],
            categories: [fixtures.groceries]
        )

        let saved = try state.save(ledger: fixtures.ledger)
        #expect(saved.orderedLines.last?.category?.id == fixtures.supplies.id)
    }

    @Test("Editing a split entry loads one draft per line")
    func editLoadsDrafts() throws {
        let fixtures = try makeFixtures()
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: fixtures.account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: fixtures.supplies),
                LedgerLineInput(amountMinor: 20_000, category: fixtures.groceries),
            ]
        )

        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [fixtures.account],
            categories: [fixtures.groceries, fixtures.supplies],
            tags: [fixtures.tag]
        )

        #expect(state.isSplit)
        #expect(state.lineDrafts?.count == 2)
        #expect(state.lineDrafts?.map(\.amountText) == ["300", "200"])
        #expect(
            state.lineDrafts?.map(\.categoryID)
                == [fixtures.supplies.id, fixtures.groceries.id]
        )
    }
}
