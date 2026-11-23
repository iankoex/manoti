//
//  WidgetSnapshotServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Widget snapshot")
struct WidgetSnapshotServiceTests {
    private struct Fixtures {
        let context: ModelContext
        let accounts: AccountService
        let ledger: LedgerService
        let budget: BudgetService
        let app: AppService
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return Fixtures(
            context: context,
            accounts: AccountService(context: context),
            ledger: LedgerService(context: context),
            budget: BudgetService(context: context),
            app: AppService(context: context)
        )
    }

    @Test("A snapshot carries the current totals and masks them in privacy mode")
    func snapshotTotalsAndPrivacy() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(
            name: "M-Pesa",
            kind: .mobileMoney,
            openingBalanceMinor: 100_000
        )
        try fixtures.ledger.record(kind: .expense, amountMinor: 25_000, account: account)

        let food = try #require(
            try CategoryService(context: fixtures.context).fetchCategories().first { $0.name == "Lunch" }
        )
        let period = try fixtures.budget.currentPeriod(
            kind: .month,
            containing: Date(),
            calendar: .current
        )
        try fixtures.budget.setEnvelope(
            category: food,
            limitMinor: 50_000,
            rolloverEnabled: false,
            in: period
        )

        let service = WidgetSnapshotService(context: fixtures.context)
        let shown = try service.makeSnapshot()

        #expect(shown.netWorthText.contains("750"))
        #expect(shown.monthSpendText.contains("250"))
        #expect(shown.safeToSpendText != "—")
        #expect(!shown.isPrivacyModeEnabled)

        try fixtures.app.setPrivacyModeEnabled(true)
        let hidden = try service.makeSnapshot()

        #expect(hidden.netWorthText == "••••")
        #expect(hidden.monthSpendText == "••••")
        #expect(hidden.safeToSpendText == "••••")
        #expect(hidden.isPrivacyModeEnabled)
    }

    @Test("Taking a snapshot never creates a budget period")
    func snapshotDoesNotCreatePeriod() throws {
        let fixtures = try makeFixtures()
        _ = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let service = WidgetSnapshotService(context: fixtures.context)
        let snapshot = try service.makeSnapshot()

        #expect(snapshot.safeToSpendText == "—")
        #expect(try fixtures.context.fetchCount(FetchDescriptor<BudgetPeriod>()) == 0)
    }

    @Test("No envelopes means no safe-to-spend figure")
    func noEnvelopes() throws {
        let fixtures = try makeFixtures()
        _ = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let snapshot = try WidgetSnapshotService(context: fixtures.context).makeSnapshot()

        #expect(snapshot.safeToSpendText == "—")
    }
}
