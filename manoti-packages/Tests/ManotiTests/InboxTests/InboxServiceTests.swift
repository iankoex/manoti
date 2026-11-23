//
//  InboxServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("InboxService")
struct InboxServiceTests {
    private func makeServices() throws -> (InboxService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return (InboxService(context: context), context)
    }

    private func pendingEntry(kind: LedgerEntryKind, payee: String, in context: ModelContext) -> LedgerEntry {
        let entry = LedgerEntry(kind: kind, amountMinor: 10_000, payee: payee, source: .message)
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

    @Test("Confirming requires an account and learns the merchant")
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

        try inbox.confirm(entry, account: account, category: category)

        #expect(entry.status == .confirmed)
        #expect(entry.account?.id == account.id)

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
}
