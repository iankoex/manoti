//
//  InboxServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import EntryFormFeature

@MainActor
@Suite("InboxService")
struct InboxServiceTests {
    private func makeServices() throws -> (InboxService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return (InboxService(context: context), context)
    }

    /// Outside the seeded commute and lunch rule windows, so the fallback suggestion does not
    /// depend on what time the suite runs. (The 10,000-minor expense matched the "Evening
    /// commute" starter rule after 17:00 on weekdays.)
    private static let quietTime =
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 1, day: 5, hour: 3)
        ) ?? .distantPast

    private func pendingEntry(kind: LedgerEntryKind, payee: String, in context: ModelContext) -> LedgerEntry {
        let entry = LedgerEntry(kind: kind, amountMinor: 10_000, payee: payee, source: .message)
        entry.occurredAt = Self.quietTime
        entry.status = .needsReview
        context.insert(entry)
        return entry
    }

    @Test("An unknown income falls back to Other income")
    func incomeFallback() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .income, payee: "SOMEONE UNKNOWN", in: context)

        let suggestions = try inbox.suggestions(for: entry)

        #expect(suggestions.first?.category.name == "Other income")
    }

    @Test("An unknown expense falls back to Uncategorised")
    func expenseFallback() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "SOMEONE UNKNOWN", in: context)

        let suggestions = try inbox.suggestions(for: entry)

        #expect(suggestions.first?.category.name == "Uncategorised")
    }

    @Test("Confirming requires an account; the review save learns the merchant")
    func confirm() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Shell Bellevue", in: context)
        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(account)
        let category = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )

        #expect(throws: InboxError.missingAccount) {
            try inbox.confirm(entry, account: nil, category: category)
        }

        let form = EntryFormState(
            purpose: .review,
            entry: entry,
            accounts: [account],
            categories: [category]
        )
        form.selectedAccountID = account.id
        form.selectedCategoryID = category.id
        try form.save(ledger: LedgerService(context: context))
        try inbox.confirm(entry, account: form.selectedAccount, category: form.selectedCategory)

        #expect(entry.status == .confirmed)
        #expect(entry.account?.id == account.id)

        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        #expect(memories.first?.category?.id == category.id)
        #expect(memories.first?.timesSeen == 1)
    }

    @Test("Changing a category in the ledger teaches the merchant once")
    func editTeaches() throws {
        let (_, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(account)
        let fuel = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )
        let household = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Household" }
        )

        let entry = try ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            category: fuel,
            payee: "Shell Bellevue"
        )

        let memory = try #require(try context.fetch(FetchDescriptor<MerchantMemory>()).first)
        #expect(memory.category?.id == fuel.id)
        #expect(memory.timesSeen == 1)

        try ledger.update(
            entry,
            kind: .expense,
            amountMinor: 10_000,
            feeMinor: 0,
            account: account,
            category: household,
            payee: "Shell Bellevue",
            note: "",
            occurredAt: entry.occurredAt
        )
        #expect(memory.category?.id == household.id)
        #expect(memory.timesSeen == 2)

        // An edit that leaves the category alone must not inflate the count.
        try ledger.update(
            entry,
            kind: .expense,
            amountMinor: 10_000,
            feeMinor: 0,
            account: account,
            category: household,
            payee: "Shell Bellevue",
            note: "Corner shop",
            occurredAt: entry.occurredAt
        )
        #expect(memory.timesSeen == 2)
    }

    @Test("Review edits are applied before the entry is confirmed")
    func reviewAppliesEditsThenConfirms() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Shell", in: context)
        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(account)
        let category = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )

        let form = EntryFormState(
            purpose: .review,
            entry: entry,
            accounts: [account],
            categories: [category]
        )
        form.amountText = "250"
        form.payee = "  Shell Bellevue  "
        form.selectedAccountID = account.id
        form.selectedCategoryID = category.id

        try form.save(ledger: LedgerService(context: context))
        try inbox.confirm(entry, account: form.selectedAccount, category: form.selectedCategory)

        #expect(entry.amountMinor == 25_000)
        #expect(entry.payee == "Shell Bellevue")
        #expect(entry.status == .confirmed)
        #expect(entry.primaryCategory?.id == category.id)

        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        #expect(memories.first?.category?.id == category.id)
    }

    @Test("Ignoring removes the entry from the pending list")
    func ignore() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Unknown", in: context)

        #expect(try inbox.pending().count == 1)
        try inbox.ignore(entry)
        #expect(try inbox.pending().isEmpty)
    }

    @Test("Confirming never relabels money into another currency")
    func currencyMismatch() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Shell", in: context)
        let ugx = Account(name: "UGX wallet", kind: .mobileMoney, currencyCode: "UGX")
        context.insert(ugx)

        #expect(
            throws: InboxError.currencyMismatch(expected: "UGX", actual: "KES")
        ) {
            try inbox.confirm(entry, account: ugx, category: nil)
        }
        #expect(entry.status == .needsReview)
    }

    @Test("An archived account cannot confirm an entry")
    func archivedAccount() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Shell", in: context)
        let account = Account(name: "Old", kind: .mobileMoney)
        account.isArchived = true
        context.insert(account)

        #expect(throws: InboxError.archivedAccount) {
            try inbox.confirm(entry, account: account, category: nil)
        }
    }

    @Test("An unparsed message can be listed and dismissed")
    func unparsedMessages() throws {
        let (inbox, context) = try makeServices()
        let message = UnparsedMessage(rawText: "Good morning", sender: "M-PESA")
        context.insert(message)
        try context.save()

        #expect(try inbox.unparsed().count == 1)
        try inbox.dismiss(message)
        #expect(try inbox.unparsed().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<UnparsedMessage>()) == 1)
    }

    @Test("Clearing unreadable messages deletes visible and dismissed rows")
    func clearUnparsedMessages() throws {
        let (inbox, context) = try makeServices()
        let visible = UnparsedMessage(rawText: "Good morning", sender: "M-PESA")
        let dismissed = UnparsedMessage(rawText: "Your balance is", sender: "M-PESA")
        dismissed.isDismissed = true
        context.insert(visible)
        context.insert(dismissed)
        try context.save()

        #expect(try inbox.unparsed().count == 1)

        let deleted = try inbox.deleteAllUnparsed()

        #expect(deleted == 2)
        #expect(try inbox.unparsed().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<UnparsedMessage>()) == 0)
    }

    @Test("Ignoring remembers the message pattern and Undo forgets it")
    func ignoreRemembersShape() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Shell", in: context)
        entry.messageSender = "M-PESA"
        entry.ingestFingerprint = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Paid Ksh 100 to Shell"
        )
        try context.save()

        try inbox.ignore(entry, reason: .notATransaction)

        #expect(entry.status == .ignored)
        #expect(try inbox.autoIgnored().contains { $0.id == entry.id })
        #expect(try inbox.memories().first?.reason == .notATransaction)

        try inbox.undoAutoIgnore(entry)

        #expect(entry.status == .needsReview)
        #expect(try inbox.memories().isEmpty)
    }

    @Test("Deleting an auto-ignored row keeps the learned pattern")
    func deleteAutoIgnoredKeepsShape() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .expense, payee: "Shell", in: context)
        entry.messageSender = "M-PESA"
        entry.ingestFingerprint = TemplateFingerprint.make(
            sender: "M-PESA",
            text: "Paid Ksh 100 to Shell"
        )
        try context.save()

        try inbox.ignore(entry, reason: .notATransaction)
        #expect(try inbox.autoIgnored().count == 1)
        #expect(try inbox.memories().count == 1)

        try inbox.deleteAutoIgnored(entry)

        #expect(try inbox.autoIgnored().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
        #expect(try inbox.memories().count == 1)
    }

    @Test("Clearing auto-ignored removes only ignored message rows")
    func clearAutoIgnoredRows() throws {
        let (inbox, context) = try makeServices()
        let first = pendingEntry(kind: .expense, payee: "First", in: context)
        let second = pendingEntry(kind: .income, payee: "Second", in: context)
        let pending = pendingEntry(kind: .expense, payee: "Still pending", in: context)

        let manualIgnored = LedgerEntry(
            kind: .expense,
            amountMinor: 5_000,
            payee: "Manual",
            source: .manual
        )
        manualIgnored.status = .ignored
        context.insert(manualIgnored)
        try context.save()

        try inbox.ignore(first)
        try inbox.ignore(second)

        #expect(try inbox.autoIgnored().count == 2)

        let deleted = try inbox.deleteAllAutoIgnored()

        #expect(deleted == 2)
        #expect(try inbox.autoIgnored().isEmpty)
        #expect(try inbox.pending().map(\.id) == [pending.id])
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 2)
    }

    @Test("A same-amount entry minutes apart is a proposal, not a link")
    func possibleDuplicate() throws {
        let (inbox, context) = try makeServices()
        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(account)

        let first = pendingEntry(kind: .expense, payee: "Shell", in: context)
        first.account = account
        first.occurredAt = Self.quietTime

        let second = pendingEntry(kind: .expense, payee: "Shell", in: context)
        second.account = account
        second.occurredAt = Self.quietTime.addingTimeInterval(3 * 60)
        try context.save()

        #expect(inbox.possibleDuplicate(of: second)?.id == first.id)
        #expect(inbox.possibleDuplicate(of: first)?.id == second.id)

        second.occurredAt = Self.quietTime.addingTimeInterval(6 * 60)
        try context.save()

        #expect(inbox.possibleDuplicate(of: second) == nil)
    }

    @Test("A paired transfer leg cannot be confirmed or ignored from the Inbox")
    func pairedTransferLeg() throws {
        let (inbox, context) = try makeServices()
        let entry = pendingEntry(kind: .transferOut, payee: "Transfer", in: context)
        let transfer = Transfer()
        context.insert(transfer)
        entry.transfer = transfer
        try context.save()

        #expect(try inbox.pending().isEmpty)
        #expect(throws: InboxError.linkedTransfer) {
            try inbox.ignore(entry)
        }
    }

    @Test("Review pre-fills the account the merchant was last filed under")
    func suggestedAccount() throws {
        let (inbox, context) = try makeServices()
        let mpesa = Account(name: "M-Pesa", kind: .mobileMoney)
        let other = Account(name: "Other wallet", kind: .mobileMoney)
        context.insert(mpesa)
        context.insert(other)
        let fuel = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )
        try CategoriserService(context: context).learn(
            payee: "Shell Bellevue",
            category: fuel,
            account: mpesa
        )

        let entry = pendingEntry(kind: .expense, payee: "Shell Bellevue", in: context)
        #expect(inbox.suggestedAccount(for: entry)?.id == mpesa.id)
    }

    @Test("The auto-apply toggle round-trips through the merchant memory")
    func autoApplyRoundTrip() throws {
        let (inbox, context) = try makeServices()
        let fuel = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )
        try CategoriserService(context: context).learn(payee: "Shell Bellevue", category: fuel)

        #expect(inbox.autoApply(for: "Shell Bellevue") == false)
        try inbox.setAutoApply(true, for: "Shell Bellevue")
        #expect(inbox.autoApply(for: "Shell Bellevue"))
    }
}
