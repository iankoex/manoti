//
//  LineAggregationTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Line aggregation")
struct LineAggregationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeServices() throws -> (InsightsService, BudgetService, LedgerService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (
            InsightsService(context: context),
            BudgetService(context: context),
            LedgerService(context: context),
            context
        )
    }

    private func makeCategory(
        _ name: String,
        isFixed: Bool = false,
        in context: ModelContext
    ) -> SpendingCategory {
        let category = SpendingCategory(
            name: name,
            symbolName: "circle",
            colorHex: "#FF9500",
            isFixed: isFixed
        )
        context.insert(category)
        return category
    }

    private func makeAccount(
        _ name: String,
        ownership: AccountOwnership = .personal,
        in context: ModelContext
    ) -> Account {
        let account = Account(name: name, kind: .bank, ownership: ownership)
        context.insert(account)
        return account
    }

    @Test("A split receipt is totalled once and its lines land in their categories")
    func splitTotals() throws {
        let (insights, _, ledger, context) = try makeServices()
        let account = makeAccount("Bank", in: context)
        let fixed = makeCategory("Rent", isFixed: true, in: context)
        let variable = makeCategory("Food", in: context)
        let now = Date()

        _ = try ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 20_000, category: fixed),
                LedgerLineInput(amountMinor: 30_000, category: variable),
            ],
            occurredAt: now.addingTimeInterval(-60)
        )

        let total = try insights.total(
            kind: .expense,
            from: now.addingTimeInterval(-60),
            to: now.addingTimeInterval(60),
            displayCurrency: .kes
        )

        #expect(total.amount.minorUnits == 50_000)

        let comparison = try insights.comparison(
            kind: .month,
            containing: now,
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(comparison.fixedCurrent.minorUnits == 20_000)
        #expect(comparison.variableCurrent.minorUnits == 30_000)
    }

    @Test("A fee counts as variable spending so the split still adds up")
    func feeIsVariable() throws {
        let (insights, _, ledger, context) = try makeServices()
        let account = makeAccount("Bank", in: context)
        let fixed = makeCategory("Rent", isFixed: true, in: context)
        let variable = makeCategory("Food", in: context)
        let now = Date()

        _ = try ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            feeMinor: 2_000,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 20_000, category: fixed),
                LedgerLineInput(amountMinor: 30_000, category: variable),
            ],
            occurredAt: now.addingTimeInterval(-60)
        )

        let comparison = try insights.comparison(
            kind: .month,
            containing: now,
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(comparison.fixedCurrent.minorUnits == 20_000)
        #expect(comparison.variableCurrent.minorUnits == 32_000)
    }

    @Test("Company spending is hidden from personal totals and budgets but kept in all totals")
    func companyScoping() throws {
        let (insights, budget, ledger, context) = try makeServices()
        let personal = makeAccount("Personal", in: context)
        let company = makeAccount("Company", ownership: .company, in: context)
        let supplies = makeCategory("Supplies", in: context)
        let now = Date()
        let period = try budget.currentPeriod(kind: .month, containing: now, calendar: calendar)
        try budget.setEnvelope(category: supplies, limitMinor: 100_000, rolloverEnabled: false, in: period)

        _ = try ledger.record(
            kind: .expense,
            amountMinor: 30_000,
            account: personal,
            lines: [LedgerLineInput(amountMinor: 30_000, category: supplies)],
            occurredAt: now
        )
        _ = try ledger.record(
            kind: .expense,
            amountMinor: 70_000,
            account: company,
            lines: [LedgerLineInput(amountMinor: 70_000, category: supplies)],
            occurredAt: now
        )

        let start = now.addingTimeInterval(-60)
        let end = now.addingTimeInterval(60)

        let personalTotal = try insights.total(
            kind: .expense, from: start, to: end, displayCurrency: .kes)
        let allTotal = try insights.total(
            kind: .expense, from: start, to: end, displayCurrency: .kes, ownership: .all)

        #expect(personalTotal.amount.minorUnits == 30_000)
        #expect(allTotal.amount.minorUnits == 100_000)
        #expect(try budget.actualMinor(for: supplies, in: period) == 30_000)
    }

    @Test("An uncategorised line is reported separately from envelope spend")
    func uncategorisedLine() throws {
        let (_, budget, ledger, context) = try makeServices()
        let account = makeAccount("Bank", in: context)
        let groceries = makeCategory("Groceries", in: context)
        let now = Date()
        let period = try budget.currentPeriod(kind: .month, containing: now, calendar: calendar)
        try budget.setEnvelope(category: groceries, limitMinor: 100_000, rolloverEnabled: false, in: period)

        _ = try ledger.record(
            kind: .expense,
            amountMinor: 50_000,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 20_000, category: groceries),
                LedgerLineInput(amountMinor: 30_000),
            ],
            occurredAt: now
        )

        let summary = try budget.summary(for: period, displayCurrency: .kes, now: now)

        #expect(summary.envelopes.first?.spent.minorUnits == 20_000)
        #expect(summary.unbudgeted.minorUnits == 30_000)
        #expect(summary.totalSpent.minorUnits == 20_000)
    }
}
