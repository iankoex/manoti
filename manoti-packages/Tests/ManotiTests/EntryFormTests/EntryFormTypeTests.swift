//
//  EntryFormTypeTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import EntryFormFeature

@MainActor
@Suite("Entry form type switching")
struct EntryFormTypeTests {
    private struct Services {
        let accounts: AccountService
        let categories: CategoryService
        let tags: TagService
        let ledger: LedgerService
        let transfers: TransferService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return Services(
            accounts: AccountService(context: context),
            categories: CategoryService(context: context),
            tags: TagService(context: context),
            ledger: LedgerService(context: context),
            transfers: TransferService(context: context),
            context: context
        )
    }

    private func state(
        purpose: EntryFormState.Purpose,
        entry: LedgerEntry,
        services: Services
    ) -> EntryFormState {
        let state = EntryFormState(purpose: purpose, entry: entry)
        state.reload(
            accountService: services.accounts,
            categoryService: services.categories,
            tagService: services.tags
        )
        return state
    }

    private func incomeEntry(account: Account, amountMinor: Int64, in context: ModelContext) -> LedgerEntry {
        let entry = LedgerEntry(
            kind: .income,
            amountMinor: amountMinor,
            currencyCode: account.currencyCode,
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            payee: "IM BANK LIMITED- APP",
            source: .message
        )
        entry.account = account
        entry.externalRef = "UKP6H2R80I"
        entry.status = .needsReview
        context.insert(entry)
        entry.attachSingleLine(category: nil, in: context)
        return entry
    }

    @Test("Review can turn an income into a transfer, asking for the source")
    func reviewIncomeToTransfer() throws {
        let services = try makeServices()
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try services.accounts.create(name: "IM Bank", kind: .bank)
        let entry = incomeEntry(account: mobile, amountMinor: 200_000, in: services.context)
        try services.context.save()

        let state = state(purpose: .review, entry: entry, services: services)
        #expect(state.type == .income)
        #expect(state.isTypeEditable)

        state.setType(.transfer)
        #expect(state.type == .transfer)
        #expect(state.kind == .transferIn)
        #expect(state.isTransferForm)
        #expect(!state.showsCategory)
        #expect(state.transferDestinationAccount?.id == mobile.id)
        #expect(state.transferSourceAccount == nil)
        #expect(!state.canSave)

        state.counterpartAccountID = bank.id
        #expect(state.transferSourceAccount?.id == bank.id)
        #expect(state.canSave)

        // Both sides keep every account; the selected one is disabled in the view, not
        // filtered out, so From can still change after To is chosen.
        #expect(state.knownSideAccounts.count == 2)
        #expect(state.counterpartAccounts.count == 2)
        #expect(state.knownSideAccounts.contains { $0.id == bank.id })
        #expect(state.counterpartAccounts.contains { $0.id == mobile.id })

        _ = try state.save(ledger: services.ledger, transfer: services.transfers)

        #expect(entry.kind == .transferIn)
        #expect(entry.transfer != nil)
        #expect(entry.orderedLines.isEmpty)
        #expect(try services.transfers.linkedTransfers().count == 1)
        #expect(try InboxService(context: services.context).pending().isEmpty)
    }

    @Test("Edit can turn an expense into a transfer, asking for the destination")
    func editExpenseToTransfer() throws {
        let services = try makeServices()
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try services.accounts.create(name: "IM Bank", kind: .bank)

        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 28_000,
            feeMinor: 500,
            currencyCode: "KES",
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            payee: "Family Bank Pesa Pap",
            source: .message
        )
        entry.account = mobile
        entry.status = .confirmed
        services.context.insert(entry)

        let category = try #require(
            try services.categories.fetchCategories().first { $0.kind == .expense }
        )
        entry.attachSingleLine(category: category, in: services.context)
        try services.context.save()

        let state = state(purpose: .edit, entry: entry, services: services)
        #expect(state.type == .expense)

        state.setType(.transfer)
        #expect(state.kind == .transferOut)
        #expect(state.transferSourceAccount?.id == mobile.id)
        #expect(state.transferDestinationAccount == nil)

        state.counterpartAccountID = bank.id
        #expect(state.canSave)

        _ = try state.save(ledger: services.ledger, transfer: services.transfers)

        #expect(entry.kind == .transferOut)
        #expect(entry.status == .confirmed)
        #expect(entry.transfer?.inTransaction?.account?.id == bank.id)
        #expect(entry.feeMinor == 500)
        #expect(entry.orderedLines.isEmpty)
    }

    @Test("From can take the account currently on To, clearing To")
    func fromTakesToAccount() throws {
        let services = try makeServices()
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try services.accounts.create(name: "Test Bank", kind: .bank)
        let third = try services.accounts.create(name: "Testing Account", kind: .bank)

        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 10_000,
            currencyCode: "KES",
            occurredAt: Date(),
            payee: "Test",
            source: .manual
        )
        entry.account = mobile
        services.context.insert(entry)
        entry.attachSingleLine(category: nil, in: services.context)
        try services.context.save()

        let state = state(purpose: .edit, entry: entry, services: services)
        state.setType(.transfer)
        state.counterpartAccountID = bank.id

        #expect(state.transferSourceAccount?.id == mobile.id)
        #expect(state.transferDestinationAccount?.id == bank.id)
        // Every account stays in both lists; the view dims the other side, it does not
        // remove it.
        #expect(state.knownSideAccounts.count == 3)
        #expect(state.counterpartAccounts.count == 3)

        // From always accepts a tap. Taking the To account clears To.
        state.selectTransferSource(bank.id)

        #expect(state.transferSourceAccount?.id == bank.id)
        #expect(state.transferDestinationAccount == nil)
        #expect(state.transferDestinationID == nil)

        state.selectTransferDestination(third.id)

        #expect(state.transferSourceAccount?.id == bank.id)
        #expect(state.transferDestinationAccount?.id == third.id)
    }

    @Test("Switching back to Expense clears the transfer side")
    func switchBack() throws {
        let services = try makeServices()
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try services.accounts.create(name: "IM Bank", kind: .bank)
        let entry = incomeEntry(account: mobile, amountMinor: 100_000, in: services.context)
        try services.context.save()

        let state = state(purpose: .review, entry: entry, services: services)
        state.setType(.transfer)
        state.counterpartAccountID = bank.id

        state.setType(.expense)

        #expect(state.type == .expense)
        #expect(state.kind == .expense)
        #expect(state.counterpartAccountID == nil)
        #expect(state.showsCategory)
        #expect(state.transferSourceAccount == nil)
    }

    @Test("An unpaired transfer leg can become an expense")
    func transferLegToExpense() throws {
        let services = try makeServices()
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let entry = LedgerEntry(
            kind: .transferOut,
            amountMinor: 100_000,
            currencyCode: "KES",
            occurredAt: Date(),
            payee: "IM BANK",
            source: .message
        )
        entry.account = mobile
        entry.externalRef = "5989CBLR1498"
        entry.status = .needsReview
        services.context.insert(entry)
        try services.context.save()

        let state = state(purpose: .edit, entry: entry, services: services)
        #expect(state.type == .transfer)
        #expect(state.isTypeEditable)

        state.setType(.expense)
        #expect(state.kind == .expense)
        #expect(state.showsCategory)

        let category = try #require(
            try services.categories.fetchCategories().first { $0.kind == .expense }
        )
        state.selectedCategoryID = category.id
        #expect(state.canSave)

        try state.save(ledger: services.ledger)

        #expect(entry.kind == .expense)
        #expect(entry.orderedLines.count == 1)
        #expect(entry.primaryCategory?.id == category.id)
    }

    @Test("Split lines and tags warn before a conversion")
    func conversionWarning() throws {
        let services = try makeServices()
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = incomeEntry(account: mobile, amountMinor: 100_000, in: services.context)

        let first = try #require(entry.orderedLines.first)
        let second = LedgerEntryLine(amountMinor: 20_000)
        services.context.insert(second)
        second.entry = entry
        entry.lines = [first, second]

        let tag = Tag(name: "Job", colorHex: "#27AE60", symbolName: "tag")
        services.context.insert(tag)
        first.tags = [tag]
        try services.context.save()

        let state = state(purpose: .review, entry: entry, services: services)
        #expect(state.conversionDropsSplitOrTags == false)

        state.setType(.transfer)
        #expect(state.conversionDropsSplitOrTags)
    }
}
