//
//  EntryFormStateTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import EntryFormFeature

@MainActor
@Suite("Add form")
struct EntryFormStateTests {
    private func makeState() throws -> (EntryFormState, AccountService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        let accounts = AccountService(context: context)
        let state = EntryFormState()
        state.reload(accountService: accounts, categoryService: CategoryService(context: context))
        return (state, accounts, context)
    }

    @Test("Expense and income groups are disjoint")
    func kindFiltering() throws {
        let (state, _, _) = try makeState()

        state.setKind(.expense)
        #expect(state.visibleGroups.contains { $0.name == "Food" })
        #expect(!state.visibleGroups.contains { $0.name == "Income" })
        #expect(state.availableCategories.allSatisfy { $0.kind == .expense })

        state.setKind(.income)
        #expect(state.visibleGroups.contains { $0.name == "Income" })
        #expect(!state.visibleGroups.contains { $0.name == "Food" })
        #expect(state.availableCategories.allSatisfy { $0.kind == .income })
    }

    @Test("Changing kind clears a category from the other kind")
    func clearsMismatchedSelection() throws {
        let (state, _, _) = try makeState()

        state.setKind(.expense)
        let lunch = try #require(state.availableCategories.first { $0.name == "Lunch" })
        state.selectedCategoryID = lunch.id
        #expect(state.selectedCategory == lunch)

        state.setKind(.income)
        #expect(state.selectedCategoryID == nil)
        #expect(state.selectedCategory == nil)
    }

    @Test("The keypad can edit the fee without touching the amount")
    func feeKeypad() throws {
        let (state, _, _) = try makeState()

        state.activeField = .fee
        for key in ["1", "2", ".", "5"] {
            state.press(key)
        }

        #expect(state.feeText == "12.5")
        #expect(state.amountText.isEmpty)

        state.activeField = .amount
        state.press("9")
        #expect(state.amountText == "9")
        #expect(state.feeText == "12.5")
    }

    @Test("Saving never attaches a category from the other kind")
    func saveDropsMismatchedCategory() throws {
        let (state, accounts, context) = try makeState()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        state.reload(accountService: accounts, categoryService: CategoryService(context: context))
        let lunch = try #require(state.availableCategories.first { $0.name == "Lunch" })

        state.amountText = "100"
        state.selectedAccountID = account.id
        state.setKind(.income)
        state.selectedCategoryID = lunch.id

        let entry = try state.save(ledger: LedgerService(context: context))

        #expect(entry.category == nil)
        #expect(entry.kind == .income)
    }
}
