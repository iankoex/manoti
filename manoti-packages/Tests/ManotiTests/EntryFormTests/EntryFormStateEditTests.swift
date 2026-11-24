//
//  EntryFormStateEditTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import EntryFormFeature

@MainActor
@Suite("Entry form editing")
struct EntryFormStateEditTests {
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

    @discardableResult
    private func makeCategory(
        _ name: String,
        sortIndex: Int = 0,
        in context: ModelContext
    ) -> SpendingCategory {
        let group = CategoryGroup(name: "Test group", symbolName: "square.grid.2x2", colorHex: "#FF9500")
        context.insert(group)

        let category = SpendingCategory(
            name: name,
            symbolName: "circle",
            colorHex: "#FF9500",
            sortIndex: sortIndex
        )
        category.group = group
        context.insert(category)
        return category
    }

    @Test("Only matching kind categories are offered, and the current one is kept")
    func kindFilteredCategories() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let expense = makeCategory("Food", in: fixtures.context)
        let income = makeCategory("Salary", sortIndex: 1, in: fixtures.context)
        income.kind = .income
        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 1_000,
            account: account,
            category: expense
        )

        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [account],
            categories: [expense, income]
        )

        #expect(state.availableCategories.map(\.id) == [expense.id])

        state.kind = .income
        #expect(state.availableCategories.contains { $0.id == income.id })
        #expect(!state.availableCategories.contains { $0.id == expense.id })
        #expect(state.selectedCategory?.id == expense.id)
        #expect(!state.canSave)
    }

    @Test("Opening an ordinary entry prefills every editable field")
    func prefill() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let category = makeCategory("Food", in: fixtures.context)
        let occurredAt = Date(timeIntervalSince1970: 500)

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 150_000,
            feeMinor: 2_500,
            account: account,
            category: category,
            payee: "Shop",
            note: "Milk",
            occurredAt: occurredAt
        )
        entry.payee = "  Shop  "
        entry.note = "  Milk  "

        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [account],
            categories: [category]
        )

        #expect(state.kind == .expense)
        #expect(state.amountText == "1500")
        #expect(state.feeText == "25")
        #expect(state.occurredAt == occurredAt)
        #expect(state.selectedAccountID == account.id)
        #expect(state.selectedCategoryID == category.id)
        #expect(state.payee == "  Shop  ")
        #expect(state.note == "  Milk  ")
        #expect(state.isKindEditable)
        #expect(state.kindOptions == [.expense, .income])
        #expect(state.canSave)
    }

    @Test("The entry's account survives until the picker options are loaded")
    func accountPrefillSurvivesReload() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: account)

        // The sheet creates the state before the services are read.
        let state = EntryFormState(purpose: .edit, entry: entry)
        #expect(state.selectedAccountID == account.id)

        state.reload(
            accountService: fixtures.accounts,
            categoryService: CategoryService(context: fixtures.context)
        )

        #expect(state.selectedAccountID == account.id)
        #expect(state.canSave)
    }

    @Test("The first keypad press replaces a prefilled amount")
    func prefilledAmountIsReplaced() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 150_000, account: account)
        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])

        state.press("7")
        #expect(state.amountText == "7")
    }

    @Test("Amounts parse through MoneyParser in the selected account's currency")
    func parsing() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: account)
        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])

        state.amountText = "1,500.50"
        state.feeText = "10.25"

        #expect(state.parsedAmount?.minorUnits == 150_050)
        #expect(state.parsedAmount?.currency == account.currency)
        #expect(state.parsedFeeMinor == 1_025)
        #expect(state.canSave)
    }

    @Test("Save stays disabled for missing or non-positive amounts and negative fees")
    func validation() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: account)
        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])

        state.amountText = ""
        #expect(!state.canSave)
        #expect(state.validationMessage == "Enter a valid amount.")

        state.amountText = "0"
        #expect(!state.canSave)
        #expect(state.validationMessage == "Enter an amount greater than zero.")

        state.amountText = "-5"
        #expect(!state.canSave)
        #expect(state.validationMessage == "Enter an amount greater than zero.")

        state.amountText = "10"
        state.feeText = "-1"
        #expect(!state.canSave)
        #expect(state.validationMessage == "Enter a fee of zero or more.")
    }

    @Test("An entry without an active account cannot be saved")
    func missingAccount() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let unrouted = LedgerEntry(kind: .expense, amountMinor: 100, currencyCode: "KES")
        unrouted.status = .needsReview
        fixtures.context.insert(unrouted)

        let state = EntryFormState(purpose: .edit, entry: unrouted, accounts: [account])
        #expect(state.selectedAccountID == nil)
        #expect(!state.canSave)
        #expect(state.validationMessage == "Choose an account.")
        #expect(throws: EntryFormError.missingAccount) {
            try state.save(ledger: fixtures.ledger)
        }

        let routed = try fixtures.ledger.record(kind: .expense, amountMinor: 100, account: account)
        let withoutAccounts = EntryFormState(purpose: .edit, entry: routed)
        withoutAccounts.setOptions(accounts: [], groups: [], categories: [])
        #expect(withoutAccounts.selectedAccountID == nil)
        #expect(!withoutAccounts.canSave)
        #expect(withoutAccounts.validationMessage == "No active accounts available.")
        #expect(throws: EntryFormError.missingAccount) {
            try withoutAccounts.save(ledger: fixtures.ledger)
        }
    }

    @Test("A review entry without an account starts on the first matching account")
    func reviewSelectsFirstAccount() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = LedgerEntry(kind: .expense, amountMinor: 10_000, currencyCode: "KES")
        entry.status = .needsReview
        fixtures.context.insert(entry)

        let state = EntryFormState(purpose: .review, entry: entry, accounts: [account])

        #expect(state.selectedAccountID == account.id)
        #expect(state.canSave)
    }

    @Test("Archived accounts are excluded from the picker")
    func archivedAccountsExcluded() throws {
        let fixtures = try makeFixtures()
        let active = try fixtures.accounts.create(name: "Active", kind: .bank)
        let archived = try fixtures.accounts.create(name: "Old", kind: .bank)
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: active)
        let onArchived = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: archived)

        try fixtures.accounts.archive(archived)

        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [archived, active])
        #expect(state.accounts.map(\.id) == [active.id])
        #expect(state.selectedAccountID == active.id)

        let archivedState = EntryFormState(purpose: .edit, entry: onArchived, accounts: [active, archived])
        #expect(archivedState.selectedAccountID == nil)
        #expect(!archivedState.canSave)
        #expect(archivedState.validationMessage == "Choose an account.")
    }

    @Test("Accounts in another currency are excluded from the picker")
    func currencyAccountsExcluded() throws {
        let fixtures = try makeFixtures()
        let kes = try fixtures.accounts.create(name: "KES wallet", kind: .mobileMoney)
        let usd = try fixtures.accounts.create(name: "USD bank", kind: .bank, currencyCode: "USD")
        let entry = try fixtures.ledger.record(kind: .expense, amountMinor: 10_000, account: kes)

        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [usd, kes])

        #expect(state.accounts.map(\.id) == [kes.id])
        #expect(state.selectedAccountID == kes.id)
    }

    @Test("Saving applies the form and trims the payee and note")
    func save() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "KES wallet", kind: .mobileMoney)
        let replacement = try fixtures.accounts.create(name: "Second KES wallet", kind: .mobileMoney)
        let category = makeCategory("Food", in: fixtures.context)
        let occurredAt = Date(timeIntervalSince1970: 2_000)

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            category: category,
            payee: "Old",
            note: "Old note",
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [account, replacement],
            categories: [category]
        )

        state.kind = .income
        state.amountText = "2,000.50"
        state.feeText = "10"
        state.occurredAt = occurredAt
        state.selectedAccountID = replacement.id
        state.selectedCategoryID = nil
        state.payee = "  New payee  "
        state.note = "  New note  "

        let saved = try state.save(ledger: fixtures.ledger)

        #expect(saved === entry)
        #expect(entry.kind == .income)
        #expect(entry.amountMinor == 200_050)
        #expect(entry.feeMinor == 1_000)
        #expect(entry.account?.id == replacement.id)
        #expect(entry.currencyCode == "KES")
        #expect(entry.category == nil)
        #expect(entry.payee == "New payee")
        #expect(entry.note == "New note")
        #expect(entry.occurredAt == occurredAt)
    }

    @Test("A matching category clears a mismatched one and enables updating")
    func choosingMatchingCategoryEnablesSave() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let expense = makeCategory("Food", in: fixtures.context)
        let income = makeCategory("Salary", sortIndex: 1, in: fixtures.context)
        income.kind = .income

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            category: income
        )

        let state = EntryFormState(
            purpose: .edit,
            entry: entry,
            accounts: [account],
            categories: [expense, income]
        )

        #expect(!state.canSave)
        #expect(state.validationMessage == "Choose a category that matches this entry kind.")

        state.selectedCategoryID = expense.id

        #expect(state.canSave)
        #expect(state.validationMessage == nil)
    }

    @Test("A linked entry is read-only here")
    func linkedEntryCannotSave() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .transferOut, amountMinor: 10_000, account: account)

        let transfer = Transfer()
        fixtures.context.insert(transfer)
        entry.transfer = transfer

        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])
        #expect(state.isLinkedEntry)
        #expect(!state.isKindEditable)
        #expect(state.kindOptions == [.transferOut])
        #expect(!state.canSave)
        #expect(
            state.validationMessage
                == "This entry belongs to a transfer, loan or investment. Change it from its own screen."
        )
        #expect(throws: EntryFormError.linkedEntry) {
            try state.save(ledger: fixtures.ledger)
        }
    }

    @Test("Adjustments keep their kind and signed amount")
    func adjustmentKindIsFixed() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .adjustment, amountMinor: -12_550, account: account)

        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])
        #expect(state.kind == .adjustment)
        #expect(!state.isKindEditable)
        #expect(state.kindOptions == [.adjustment])
        #expect(state.amountText == "-125.5")
        #expect(state.parsedAmount?.minorUnits == -12_550)
        #expect(state.canSave)

        state.amountText = "0"
        #expect(!state.canSave)
        #expect(state.validationMessage == "Enter a non-zero amount.")
    }

    @Test("The sign button flips an adjustment")
    func toggleSign() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try fixtures.ledger.record(kind: .adjustment, amountMinor: -12_550, account: account)
        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])

        state.toggleAmountSign()
        #expect(state.amountText == "125.5")
        #expect(state.parsedAmount?.minorUnits == 12_550)

        state.toggleAmountSign()
        #expect(state.amountText == "-125.5")
        #expect(state.parsedAmount?.minorUnits == -12_550)
    }

    @Test("A transfer entry hides the category and keeps the one it already has")
    func transferKeepsCategory() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let category = makeCategory("Transfer fee", in: fixtures.context)

        let entry = try fixtures.ledger.record(
            kind: .transferOut,
            amountMinor: 10_000,
            account: account,
            category: category
        )
        entry.status = .needsReview

        let state = EntryFormState(
            purpose: .review,
            entry: entry,
            accounts: [account],
            categories: [category]
        )

        #expect(!state.showsCategory)
        state.amountText = "200"

        let saved = try state.save(ledger: fixtures.ledger)

        #expect(saved === entry)
        #expect(entry.amountMinor == 20_000)
        #expect(entry.category?.id == category.id)
    }

    @Test("An archived current category survives a save")
    func archivedCategoryIsPreserved() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let category = makeCategory("Old category", in: fixtures.context)
        category.isArchived = true

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            category: category
        )

        let state = EntryFormState(purpose: .edit, entry: entry, accounts: [account])
        #expect(state.selectedCategory?.id == category.id)
        #expect(state.pinnedCategoryForPicker?.id == category.id)

        try state.save(ledger: fixtures.ledger)

        #expect(entry.category?.id == category.id)
    }

    @Test("Review accepts a suggestion without touching an existing category")
    func suggestionOnlyFillsAnEmptyCategory() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let category = makeCategory("Food", in: fixtures.context)

        let entry = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            payee: "Shell"
        )
        entry.status = .needsReview

        let state = EntryFormState(purpose: .review, entry: entry, accounts: [account], categories: [category])
        state.applySuggestion(
            CategorySuggestion(category: category, confidence: 0.82, reason: "Near lunch")
        )

        #expect(state.selectedCategoryID == category.id)
        #expect(state.suggestionNote?.contains("82%") == true)
    }
}
