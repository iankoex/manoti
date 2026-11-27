//
//  InsightsServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("InsightsService")
struct InsightsServiceTests {
    private func makeServices() throws -> (AccountService, LedgerService, InsightsService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (
            AccountService(context: context),
            LedgerService(context: context),
            InsightsService(context: context),
            context
        )
    }

    @Test("A period total excludes transfers and adds the fee")
    func periodTotal() throws {
        let (accounts, ledger, insights, _) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let now = Date()
        try ledger.record(kind: .expense, amountMinor: 10_000, feeMinor: 830, account: account, occurredAt: now)
        try ledger.record(kind: .income, amountMinor: 50_000, account: account, occurredAt: now)
        try ledger.record(kind: .transferOut, amountMinor: 99_000, account: account, occurredAt: now)

        let start = now.addingTimeInterval(-3_600)
        let end = now.addingTimeInterval(3_600)
        let total = try insights.total(kind: .expense, from: start, to: end, displayCurrency: .kes)

        #expect(total.missingRates.isEmpty)
        #expect(total.amount.minorUnits == 10_830)
    }

    @Test("Needs-review rows are not counted as spending")
    func needsReviewExcluded() throws {
        let (accounts, ledger, insights, context) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        try ledger.record(kind: .expense, amountMinor: 10_000, account: account)
        let pending = LedgerEntry(kind: .expense, amountMinor: 20_000)
        context.insert(pending)
        pending.account = account
        pending.status = .needsReview
        try context.save()

        let now = Date()
        let total = try insights.total(
            kind: .expense,
            from: now.addingTimeInterval(-3_600),
            to: now.addingTimeInterval(3_600),
            displayCurrency: .kes
        )
        let daily = try insights.dailySpend(days: 1, displayCurrency: .kes)

        #expect(total.amount.minorUnits == 10_000)
        #expect(daily.last?.total.minorUnits == 10_000)
    }

    @Test("Income totals subtract the fee")
    func incomeTotalSubtractsFee() throws {
        let (accounts, ledger, insights, _) = try makeServices()
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let now = Date()
        try ledger.record(kind: .income, amountMinor: 50_000, feeMinor: 830, account: account, occurredAt: now)

        let total = try insights.total(
            kind: .income,
            from: now.addingTimeInterval(-3_600),
            to: now.addingTimeInterval(3_600),
            displayCurrency: .kes
        )

        #expect(total.amount.minorUnits == 49_170)
    }

    @Test("Period totals use the rate current on each entry date")
    func historicalRates() throws {
        let (accounts, ledger, insights, context) = try makeServices()
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        let dayOne = Date(timeIntervalSince1970: 1_000_000)
        let dayTwo = Date(timeIntervalSince1970: 2_000_000)

        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: dayOne)
        )
        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 132_000_000, asOf: dayTwo)
        )
        try context.save()

        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: dayOne)
        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: dayTwo)

        let total = try insights.total(
            kind: .expense,
            from: dayOne.addingTimeInterval(-1),
            to: dayTwo.addingTimeInterval(3_600),
            displayCurrency: .kes
        )

        // USD 100 at 130 plus USD 100 at 132, not both at the newest 132 rate.
        #expect(total.amount.minorUnits == 2_620_000)
    }

    @Test("Daily spend uses the rate current on each day")
    func dailySpendHistoricalRates() throws {
        let (accounts, ledger, insights, context) = try makeServices()
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let dayOne = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne) ?? dayOne

        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: dayOne)
        )
        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 132_000_000, asOf: dayTwo)
        )
        try context.save()

        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: dayOne)
        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: dayTwo)

        let days = try insights.dailySpend(
            days: 2,
            displayCurrency: .kes,
            calendar: calendar,
            now: dayTwo.addingTimeInterval(3_600)
        )

        #expect(days.count == 2)
        #expect(days[0].total.minorUnits == 1_300_000)
        #expect(days[1].total.minorUnits == 1_320_000)
        #expect(days[0].missingRates.isEmpty)
        #expect(days[1].missingRates.isEmpty)
    }

    @Test("A missing historical rate is reported and shown 1:1 in major units")
    func missingHistoricalRateIsReported() throws {
        let (accounts, ledger, insights, _) = try makeServices()
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        let dayOne = Date(timeIntervalSince1970: 1_000_000)
        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: dayOne)

        let total = try insights.total(
            kind: .expense,
            from: dayOne.addingTimeInterval(-1),
            to: dayOne.addingTimeInterval(3_600),
            displayCurrency: CurrencyCatalog.currency(for: "UGX")
        )

        #expect(total.missingRates == ["USD"])
        // USD 100.00 becomes UGX 100 (100 minor units), not UGX 10,000.
        #expect(total.amount.currency.code == "UGX")
        #expect(total.amount.minorUnits == 100)
    }

    @Test("A rate added later does not change an earlier total")
    func laterRateDoesNotChangeEarlierTotal() throws {
        let (accounts, ledger, insights, context) = try makeServices()
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let dayOne = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne) ?? dayOne

        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: dayOne)

        let before = try insights.total(
            kind: .expense,
            from: dayOne.addingTimeInterval(-1),
            to: dayOne.addingTimeInterval(3_600),
            displayCurrency: CurrencyCatalog.currency(for: "UGX")
        )

        #expect(before.missingRates == ["USD"])
        #expect(before.amount.minorUnits == 100)

        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "UGX", rateScaled: 3_700_000_000, asOf: dayTwo)
        )
        try context.save()

        let after = try insights.total(
            kind: .expense,
            from: dayOne.addingTimeInterval(-1),
            to: dayOne.addingTimeInterval(3_600),
            displayCurrency: CurrencyCatalog.currency(for: "UGX")
        )

        #expect(after.missingRates == ["USD"])
        #expect(after.amount.minorUnits == 100)
    }

    @Test("Daily spend marks a day whose rate is missing")
    func dailySpendMissingRate() throws {
        let (accounts, ledger, insights, _) = try makeServices()
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        try ledger.record(kind: .expense, amountMinor: 10_000, account: usd, occurredAt: day.addingTimeInterval(3_600))

        let days = try insights.dailySpend(
            days: 1,
            displayCurrency: CurrencyCatalog.currency(for: "UGX"),
            calendar: calendar,
            now: day.addingTimeInterval(7_200)
        )

        #expect(days.count == 1)
        #expect(days[0].missingRates == ["USD"])
        #expect(days[0].total.minorUnits == 100)
    }

    @Test("Loan entries stay out of expense and income totals")
    func loanEntriesAreNotTotals() throws {
        let (accounts, _, insights, context) = try makeServices()
        let loans = LoanService(context: context)
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        try loans.create(direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)
        try loans.create(direction: .borrowed, counterparty: "Brian", principalMinor: 50_000, account: account)

        let now = Date()
        let expense = try insights.total(
            kind: .expense,
            from: now.addingTimeInterval(-86_400),
            to: now.addingTimeInterval(86_400),
            displayCurrency: .kes
        )
        let income = try insights.total(
            kind: .income,
            from: now.addingTimeInterval(-86_400),
            to: now.addingTimeInterval(86_400),
            displayCurrency: .kes
        )

        #expect(expense.amount.isZero)
        #expect(income.amount.isZero)
    }

    @Test("Loan entries stay out of daily spend")
    func loanEntriesAreNotDailySpend() throws {
        let (accounts, _, insights, context) = try makeServices()
        let loans = LoanService(context: context)
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 500_000)

        try loans.create(direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        let days = try insights.dailySpend(days: 1, displayCurrency: .kes)

        #expect(days.count == 1)
        #expect(days.first?.total.isZero == true)
    }

}
