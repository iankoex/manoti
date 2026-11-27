//
//  TagServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Tag service")
struct TagServiceTests {
    private struct Fixtures {
        let tags: TagService
        let ledger: LedgerService
        let accounts: AccountService
        let context: ModelContext
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return Fixtures(
            tags: TagService(context: context),
            ledger: LedgerService(context: context),
            accounts: AccountService(context: context),
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

    @Test("Empty and duplicate names are rejected")
    func nameRules() throws {
        let fixtures = try makeFixtures()
        _ = try fixtures.tags.createTag(name: "Nakuru assignment")

        #expect(throws: TagError.emptyName) {
            try fixtures.tags.createTag(name: "   ")
        }
        #expect(throws: TagError.duplicateName) {
            try fixtures.tags.createTag(name: "nakuru ASSIGNMENT")
        }
    }

    @Test("A tag totals income, spending and the balance")
    func totals() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let tag = try fixtures.tags.createTag(name: "Nakuru assignment")
        let travel = makeCategory("Travel", in: fixtures.context)
        let income = makeCategory("Business", kind: .income, in: fixtures.context)

        _ = try fixtures.ledger.record(
            kind: .income,
            amountMinor: 100_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 100_000, category: income, tags: [tag])]
        )
        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 20_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 20_000, category: travel, tags: [tag])]
        )

        let summary = try fixtures.tags.summary(for: tag, displayCurrency: .kes)

        #expect(summary.received.minorUnits == 100_000)
        #expect(summary.spent.minorUnits == 20_000)
        #expect(summary.balance.minorUnits == 80_000)
        #expect(summary.lineCount == 2)
        #expect(summary.missingRates.isEmpty)
    }

    @Test("Foreign lines convert at their own date and report a missing rate")
    func conversion() throws {
        let fixtures = try makeFixtures()
        let kes = try fixtures.accounts.create(name: "KES Bank", kind: .bank)
        let usd = try fixtures.accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")
        let tag = try fixtures.tags.createTag(name: "Invoice 12")
        let income = makeCategory("Business", kind: .income, in: fixtures.context)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        fixtures.context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 100_000_000,
                asOf: date.addingTimeInterval(-86_400)
            )
        )
        try fixtures.context.save()

        _ = try fixtures.ledger.record(
            kind: .income,
            amountMinor: 10_000,
            account: usd,
            lines: [LedgerLineInput(amountMinor: 10_000, category: income, tags: [tag])],
            occurredAt: date
        )
        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 20_000,
            account: kes,
            lines: [LedgerLineInput(amountMinor: 20_000, category: makeCategory("Travel", in: fixtures.context), tags: [tag])],
            occurredAt: date
        )

        let summary = try fixtures.tags.summary(for: tag, displayCurrency: .kes)

        // USD 100 at KES 100 = KES 10,000 (1,000,000 minor units).
        #expect(summary.received.minorUnits == 1_000_000)
        #expect(summary.spent.minorUnits == 20_000)
        #expect(summary.missingRates.isEmpty)

        let missing = try fixtures.tags.summary(
            for: tag,
            displayCurrency: CurrencyCatalog.currency(for: "UGX")
        )
        #expect(missing.missingRates.contains("USD"))
        #expect(missing.missingRates.contains("KES"))
    }

    @Test("Unconfirmed, ignored and deleted entries are left out")
    func postingRules() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let tag = try fixtures.tags.createTag(name: "Trip")
        let travel = makeCategory("Travel", in: fixtures.context)

        let pending = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 10_000, category: travel, tags: [tag])]
        )
        pending.status = .needsReview

        let ignored = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 20_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 20_000, category: travel, tags: [tag])]
        )
        ignored.status = .ignored

        let deleted = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 40_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 40_000, category: travel, tags: [tag])]
        )
        try fixtures.ledger.delete(deleted)

        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 5_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 5_000, category: travel, tags: [tag])]
        )

        let summary = try fixtures.tags.summary(for: tag, displayCurrency: .kes)
        #expect(summary.spent.minorUnits == 5_000)
        #expect(summary.lineCount == 1)
    }

    @Test("Closing records the date and reopening clears it")
    func closeAndReopen() throws {
        let fixtures = try makeFixtures()
        let tag = try fixtures.tags.createTag(name: "Trip")
        let closedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try fixtures.tags.closeTag(tag, at: closedAt)
        #expect(tag.status == .closed)
        #expect(tag.closedAt == closedAt)
        #expect(try fixtures.tags.fetchTags().isEmpty)
        #expect(try fixtures.tags.fetchTags(includeClosed: true).count == 1)

        try fixtures.tags.reopenTag(tag)
        #expect(tag.status == .open)
        #expect(tag.closedAt == nil)
    }

    @Test("A tag in use cannot be deleted")
    func deleteRules() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Bank", kind: .bank)
        let tag = try fixtures.tags.createTag(name: "Trip")
        let travel = makeCategory("Travel", in: fixtures.context)

        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 10_000,
            account: account,
            lines: [LedgerLineInput(amountMinor: 10_000, category: travel, tags: [tag])]
        )

        #expect(throws: TagError.inUse(lineCount: 1)) {
            try fixtures.tags.deleteTag(tag)
        }

        let unused = try fixtures.tags.createTag(name: "Unused")
        try fixtures.tags.deleteTag(unused)
        #expect(try fixtures.tags.fetchTags().count == 1)
    }

    @Test("A tagged entry lists once with only this tag's share")
    func partialAttribution() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "Card", kind: .card)
        let tag = try fixtures.tags.createTag(name: "Nakuru")
        let other = try fixtures.tags.createTag(name: "Personal")
        let travel = makeCategory("Travel", in: fixtures.context)
        let food = makeCategory("Food", in: fixtures.context)

        _ = try fixtures.ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: travel, tags: [tag]),
                LedgerLineInput(amountMinor: 20_000, category: food, tags: [other]),
            ]
        )

        let entries = try fixtures.tags.entries(for: tag)
        #expect(entries.count == 1)
        #expect(entries.first?.amountMinor == 30_000)
        #expect(entries.first?.entry.amountMinor == 50_000)
    }
}
