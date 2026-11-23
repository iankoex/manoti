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

    @Test("Net worth converts every account into the display currency")
    func netWorthConversion() throws {
        let (accounts, _, insights, context) = try makeServices()

        let kesAccount = try accounts.create(name: "KES Bank", kind: .bank, openingBalanceMinor: 1_000_000)
        let usdAccount = try accounts.create(
            name: "USD Bank", kind: .bank, currencyCode: "USD", openingBalanceMinor: 10_000)

        context.insert(ExchangeRateRecord(baseCode: "KES", quoteCode: "USD", rateScaled: 7_750))
        try context.save()

        let worth = try insights.netWorth(accounts: [kesAccount, usdAccount], displayCurrency: .kes)

        // USD 100.00 at KES 129.03 per USD ≈ KES 12,903 added to KES 10,000.
        #expect(worth.missingRates.isEmpty)
        #expect(abs(worth.amount.minorUnits - 2_290_322) <= 2)
    }

    @Test("A missing rate is reported, not hidden")
    func missingRate() throws {
        let (accounts, _, insights, _) = try makeServices()
        let usdAccount = try accounts.create(
            name: "USD Bank", kind: .bank, currencyCode: "USD", openingBalanceMinor: 10_000)

        let worth = try insights.netWorth(accounts: [usdAccount], displayCurrency: .kes)

        #expect(worth.missingRates == ["USD"])
        #expect(worth.amount.minorUnits == 10_000)
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

    @Test("Net worth falls back to major units, not raw minor units")
    func netWorthMissingRateUsesMajorUnits() throws {
        let (accounts, _, insights, _) = try makeServices()
        let usd = try accounts.create(
            name: "USD Bank",
            kind: .bank,
            currencyCode: "USD",
            openingBalanceMinor: 10_000
        )

        let worth = try insights.netWorth(accounts: [usd], displayCurrency: CurrencyCatalog.currency(for: "UGX"))

        #expect(worth.missingRates == ["USD"])
        #expect(worth.amount.currency.code == "UGX")
        #expect(worth.amount.minorUnits == 100)
    }

    @Test("Borrowing leaves net worth unchanged")
    func netWorthBorrowing() throws {
        let (accounts, _, insights, context) = try makeServices()
        let loans = LoanService(context: context)
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 50_000)

        try loans.create(direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        // Cash rises by 1,000 but the liability cancels it.
        #expect(account.balance.minorUnits == 150_000)
        let worth = try insights.netWorth(accounts: [account], displayCurrency: .kes)
        #expect(worth.amount.minorUnits == 50_000)
        #expect(worth.missingRates.isEmpty)
    }

    @Test("Lending leaves net worth unchanged")
    func netWorthLending() throws {
        let (accounts, _, insights, context) = try makeServices()
        let loans = LoanService(context: context)
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 150_000)

        try loans.create(direction: .lent, counterparty: "Brenda", principalMinor: 100_000, account: account)

        // Cash falls by 1,000 but the receivable replaces it.
        #expect(account.balance.minorUnits == 50_000)
        let worth = try insights.netWorth(accounts: [account], displayCurrency: .kes)
        #expect(worth.amount.minorUnits == 150_000)
        #expect(worth.missingRates.isEmpty)
    }

    @Test("Repaying part of a loan leaves net worth unchanged")
    func netWorthPartialRepayment() throws {
        let (accounts, _, insights, context) = try makeServices()
        let loans = LoanService(context: context)
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 50_000)
        let loan = try loans.create(
            direction: .borrowed, counterparty: "Brian", principalMinor: 100_000, account: account)

        try loans.addRepayment(to: loan, amountMinor: 40_000, account: account)

        #expect(account.balance.minorUnits == 110_000)
        let worth = try insights.netWorth(accounts: [account], displayCurrency: .kes)
        #expect(worth.amount.minorUnits == 50_000)
    }

    @Test("A loan with a missing rate is reported and shown 1:1 in major units")
    func netWorthLoanMissingRate() throws {
        let (accounts, _, insights, context) = try makeServices()
        let loans = LoanService(context: context)
        let usd = try accounts.create(
            name: "USD Bank", kind: .bank, currencyCode: "USD", openingBalanceMinor: 0)
        try loans.create(direction: .lent, counterparty: "Alex", principalMinor: 10_000, account: usd)

        let worth = try insights.netWorth(accounts: [], displayCurrency: .kes)

        // USD 100.00 has no rate, so the receivable becomes KES 100.00 (10,000 minor units).
        #expect(worth.amount.currency.code == "KES")
        #expect(worth.amount.minorUnits == 10_000)
        #expect(worth.missingRates == ["USD"])
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

    @Test("Net worth ignores a future-dated rate")
    func netWorthIgnoresFutureRate() throws {
        let (accounts, _, insights, context) = try makeServices()
        let usd = try accounts.create(
            name: "USD Bank",
            kind: .bank,
            currencyCode: "USD",
            openingBalanceMinor: 10_000
        )

        context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 100_000_000,
                asOf: Date().addingTimeInterval(-86_400)
            )
        )
        context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 200_000_000,
                asOf: Date().addingTimeInterval(86_400)
            )
        )
        try context.save()

        let worth = try insights.netWorth(accounts: [usd], displayCurrency: .kes)

        // USD 100 at KES 100 = KES 10,000 (1,000,000 minor units). The future rate is ignored.
        #expect(worth.missingRates.isEmpty)
        #expect(worth.amount.minorUnits == 1_000_000)
    }

    @Test("Net worth includes an active investment at cost basis")
    func netWorthIncludesInvestment() throws {
        let (accounts, _, insights, context) = try makeServices()
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)

        let investment = Investment(
            type: .treasuryBond,
            nominalMinor: 5_000_000,
            cashInvestedMinor: 5_275_360,
            status: .active
        )
        context.insert(investment)
        let purchase = LedgerEntry(kind: .investmentOut, amountMinor: 5_275_360, occurredAt: Date())
        purchase.account = account
        context.insert(purchase)
        try context.save()

        let worth = try insights.netWorth(accounts: [account], displayCurrency: .kes)

        #expect(worth.missingRates.isEmpty)
        #expect(worth.amount.minorUnits == 10_000_000)
    }

    @Test("Net worth excludes pending and matured investments")
    func netWorthExcludesPendingAndMatured() throws {
        let (accounts, _, insights, context) = try makeServices()
        let account = try accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)

        let pending = Investment(
            type: .treasuryBond,
            nominalMinor: 5_000_000,
            cashInvestedMinor: 5_000_000,
            status: .pending
        )
        let matured = Investment(
            type: .treasuryBond,
            nominalMinor: 5_000_000,
            cashInvestedMinor: 5_000_000,
            status: .matured
        )
        context.insert(pending)
        context.insert(matured)
        try context.save()

        let worth = try insights.netWorth(accounts: [account], displayCurrency: .kes)

        #expect(worth.amount.minorUnits == 10_000_000)
    }

    @Test("A missing investment currency rate is reported and shown 1:1 in major units")
    func netWorthInvestmentMissingRate() throws {
        let (_, _, insights, context) = try makeServices()

        let investment = Investment(
            type: .treasuryBond,
            nominalMinor: 1_000_000,
            currencyCode: "USD",
            cashInvestedMinor: 1_000_000,
            status: .active
        )
        context.insert(investment)
        try context.save()

        let worth = try insights.netWorth(accounts: [], displayCurrency: .kes)

        #expect(worth.missingRates == ["USD"])
        // USD 10,000.00 has no rate, so it becomes KES 10,000.00 (1,000,000 minor units).
        #expect(worth.amount.minorUnits == 1_000_000)
    }
}
