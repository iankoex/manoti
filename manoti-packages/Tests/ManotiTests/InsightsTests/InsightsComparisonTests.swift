//
//  InsightsComparisonTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Insights comparison")
struct InsightsComparisonTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeService() throws -> (InsightsService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (InsightsService(context: context), context)
    }

    private func makeDate(
        day: Int,
        month: Int,
        year: Int = 2026,
        hour: Int = 12,
        calendar: Calendar? = nil
    ) throws -> Date {
        let calendar = calendar ?? self.calendar
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(calendar.date(from: components))
    }

    @discardableResult
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

    @discardableResult
    private func addEntry(
        _ amountMinor: Int64,
        at occurredAt: Date,
        category: SpendingCategory? = nil,
        payee: String = "",
        kind: LedgerEntryKind = .expense,
        status: LedgerEntryStatus = .confirmed,
        isSoftDeleted: Bool = false,
        currencyCode: String = "KES",
        account: Account? = nil,
        balanceAfterMinor: Int64? = nil,
        in context: ModelContext
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            kind: kind,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            occurredAt: occurredAt
        )
        entry.attachSingleLine(category: category, in: context)
        entry.payee = payee
        entry.status = status
        entry.isSoftDeleted = isSoftDeleted
        entry.account = account
        entry.balanceAfterMinor = balanceAfterMinor
        context.insert(entry)
        return entry
    }

    // MARK: - Equal-elapsed boundaries

    @Test("Day one compares a single day with the previous month's first day")
    func monthDayOne() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 1, month: 2)
        let previous = try makeDate(day: 1, month: 1)

        addEntry(100_000, at: try makeDate(day: 1, month: 2, hour: 10), in: context)
        addEntry(40_000, at: previous, in: context)
        addEntry(999_000, at: try makeDate(day: 2, month: 1, hour: 0), in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(comparison.elapsedDays == 1)
        #expect(try comparison.currentInterval.start == makeDate(day: 1, month: 2, hour: 0))
        #expect(try comparison.currentInterval.end == makeDate(day: 1, month: 2, hour: 12))
        #expect(try comparison.previousInterval.start == makeDate(day: 1, month: 1, hour: 0))
        #expect(try comparison.previousInterval.end == makeDate(day: 1, month: 1, hour: 12))
        #expect(comparison.currentTotal.minorUnits == 100_000)
        #expect(comparison.previousTotal.minorUnits == 40_000)
    }

    @Test("Day seven compares the first seven days and aligns daily points")
    func monthDaySeven() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 7, month: 11)

        addEntry(100_000, at: try makeDate(day: 1, month: 11), in: context)
        addEntry(50_000, at: try makeDate(day: 7, month: 11, hour: 10), in: context)
        addEntry(999_000, at: try makeDate(day: 8, month: 11, hour: 0), in: context)

        addEntry(40_000, at: try makeDate(day: 1, month: 10), in: context)
        addEntry(20_000, at: try makeDate(day: 7, month: 10, hour: 10), in: context)
        addEntry(999_000, at: try makeDate(day: 8, month: 10, hour: 0), in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(comparison.elapsedDays == 7)
        #expect(try comparison.currentInterval.start == makeDate(day: 1, month: 11, hour: 0))
        #expect(try comparison.currentInterval.end == makeDate(day: 7, month: 11, hour: 12))
        #expect(try comparison.previousInterval.start == makeDate(day: 1, month: 10, hour: 0))
        #expect(try comparison.previousInterval.end == makeDate(day: 7, month: 10, hour: 12))
        #expect(comparison.currentTotal.minorUnits == 150_000)
        #expect(comparison.previousTotal.minorUnits == 60_000)

        #expect(comparison.dailyPoints.count == 7)
        #expect(comparison.dailyPoints.first?.dayIndex == 1)
        #expect(try comparison.dailyPoints.first?.currentDate == makeDate(day: 1, month: 11, hour: 0))
        #expect(comparison.dailyPoints.first?.current.minorUnits == 100_000)
        #expect(comparison.dailyPoints.first?.previous.minorUnits == 40_000)
        #expect(comparison.dailyPoints.last?.dayIndex == 7)
        #expect(comparison.dailyPoints.last?.current.minorUnits == 50_000)
        #expect(comparison.dailyPoints.last?.previous.minorUnits == 20_000)
    }

    @Test("A shorter previous month caps the elapsed comparison at its last day")
    func previousMonthCappedAtMonthEnd() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 31, month: 3, hour: 23)

        addEntry(10_000, at: try makeDate(day: 28, month: 2), in: context)
        addEntry(999_000, at: try makeDate(day: 1, month: 3, hour: 0), in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(comparison.elapsedDays == 31)
        #expect(try comparison.currentInterval.start == makeDate(day: 1, month: 3, hour: 0))
        #expect(try comparison.currentInterval.end == makeDate(day: 31, month: 3, hour: 23))
        #expect(try comparison.previousInterval.start == makeDate(day: 1, month: 2, hour: 0))
        #expect(try comparison.previousInterval.end == makeDate(day: 1, month: 3, hour: 0))
        #expect(comparison.previousTotal.minorUnits == 10_000)
        #expect(comparison.dailyPoints.count == 31)
        #expect(comparison.dailyPoints.last?.previous.isZero == true)
    }

    @Test("Weeks honour the calendar's first weekday")
    func weekBoundariesHonourFirstWeekday() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 4, month: 11)

        addEntry(1_000, at: try makeDate(day: 1, month: 11), in: context)
        addEntry(2_000, at: try makeDate(day: 2, month: 11), in: context)

        let monday = try service.comparison(kind: .week, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(monday.elapsedDays == 3)
        #expect(try monday.currentInterval.start == makeDate(day: 2, month: 11, hour: 0))
        #expect(try monday.currentInterval.end == makeDate(day: 4, month: 11, hour: 12))
        #expect(try monday.previousInterval.start == makeDate(day: 26, month: 10, hour: 0))
        #expect(try monday.previousInterval.end == makeDate(day: 28, month: 10, hour: 12))
        #expect(monday.currentTotal.minorUnits == 2_000)

        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        let sunday = try service.comparison(
            kind: .week,
            containing: current,
            displayCurrency: .kes,
            calendar: sundayCalendar
        )

        #expect(sunday.elapsedDays == 4)
        #expect(try sunday.currentInterval.start == makeDate(day: 1, month: 11, hour: 0))
        #expect(try sunday.currentInterval.end == makeDate(day: 4, month: 11, hour: 12))
        #expect(try sunday.previousInterval.start == makeDate(day: 25, month: 10, hour: 0))
        #expect(try sunday.previousInterval.end == makeDate(day: 28, month: 10, hour: 12))
        #expect(sunday.currentTotal.minorUnits == 3_000)
    }

    // MARK: - Fixed and variable

    @Test("Fixed categories split from variable spending, with uncategorised as variable")
    func fixedVersusVariable() throws {
        let (service, context) = try makeService()
        let rent = makeCategory("Rent", isFixed: true, in: context)
        let food = makeCategory("Food", in: context)
        let current = try makeDate(day: 15, month: 11)

        addEntry(1_000_000, at: try makeDate(day: 2, month: 11), category: rent, in: context)
        addEntry(200_000, at: try makeDate(day: 3, month: 11), category: food, in: context)
        addEntry(50_000, at: try makeDate(day: 4, month: 11), in: context)

        addEntry(900_000, at: try makeDate(day: 2, month: 10), category: rent, in: context)
        addEntry(100_000, at: try makeDate(day: 3, month: 10), category: food, in: context)
        addEntry(10_000, at: try makeDate(day: 4, month: 10), in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(comparison.fixedCurrent.minorUnits == 1_000_000)
        #expect(comparison.fixedPrevious.minorUnits == 900_000)
        #expect(comparison.variableCurrent.minorUnits == 250_000)
        #expect(comparison.variablePrevious.minorUnits == 110_000)
        #expect(comparison.currentTotal.minorUnits == 1_250_000)
        #expect(comparison.previousTotal.minorUnits == 1_010_000)
    }

    // MARK: - Exclusions

    @Test("Ignored, deleted, transfer, loan and investment rows are excluded")
    func excludedRows() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 15, month: 11)
        let payee = "Counted"

        addEntry(10_000, at: try makeDate(day: 2, month: 11), payee: payee, in: context)
        addEntry(20_000, at: try makeDate(day: 3, month: 11), status: .ignored, in: context)
        addEntry(30_000, at: try makeDate(day: 4, month: 11), isSoftDeleted: true, in: context)
        addEntry(25_000, at: try makeDate(day: 5, month: 11), status: .needsReview, in: context)

        let transfer = Transfer(occurredAt: try makeDate(day: 6, month: 11))
        context.insert(transfer)
        let transferLeg = addEntry(40_000, at: try makeDate(day: 6, month: 11), in: context)
        transferLeg.transfer = transfer

        let loan = Loan(direction: .borrowed, counterparty: "Brian", principalMinor: 100_000)
        context.insert(loan)
        let loanLeg = addEntry(50_000, at: try makeDate(day: 7, month: 11), in: context)
        loanLeg.loan = loan

        let investment = Investment(type: .treasuryBond)
        context.insert(investment)
        let cashFlow = InvestmentCashFlow(kind: .purchase, date: try makeDate(day: 8, month: 11))
        cashFlow.investment = investment
        context.insert(cashFlow)
        let investmentLeg = addEntry(60_000, at: try makeDate(day: 8, month: 11), in: context)
        investmentLeg.investmentCashFlow = cashFlow

        addEntry(70_000, at: try makeDate(day: 9, month: 11), kind: .transferOut, in: context)
        addEntry(80_000, at: try makeDate(day: 10, month: 11), kind: .loanOut, in: context)
        addEntry(90_000, at: try makeDate(day: 11, month: 11), kind: .investmentOut, in: context)
        addEntry(100_000, at: try makeDate(day: 12, month: 11), kind: .income, in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(comparison.currentTotal.minorUnits == 10_000)
        #expect(comparison.topMerchants.count == 1)
        #expect(comparison.topMerchants.first?.payee == payee)
        #expect(comparison.topMerchants.first?.count == 1)
    }

    // MARK: - Currency

    @Test("Each entry converts at its own date and a missing rate is reported 1:1")
    func historicalRatesAndMissingRates() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 15, month: 11)
        let dayOne = try makeDate(day: 2, month: 11, hour: 0)
        let dayTwo = try makeDate(day: 3, month: 11, hour: 0)

        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: dayOne)
        )
        context.insert(
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 132_000_000, asOf: dayTwo)
        )
        try context.save()

        addEntry(10_000, at: dayOne, currencyCode: "USD", in: context)
        addEntry(10_000, at: dayTwo, currencyCode: "USD", in: context)
        addEntry(5_000, at: try makeDate(day: 4, month: 11), currencyCode: "UGX", in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        // USD 100 at 130 plus USD 100 at 132, then UGX 5,000 shown 1:1 as KES 5,000.
        #expect(comparison.currentTotal.minorUnits == 2_620_000 + 500_000)
        #expect(comparison.missingRates == ["UGX"])
    }

    // MARK: - Trailing average

    @Test("The trailing average uses up to four previous periods")
    func trailingAverageUsesFourPeriods() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 10, month: 11)

        addEntry(50_000, at: try makeDate(day: 2, month: 11), in: context)
        addEntry(100_000, at: try makeDate(day: 2, month: 10), in: context)
        addEntry(300_000, at: try makeDate(day: 2, month: 9), in: context)
        addEntry(200_000, at: try makeDate(day: 2, month: 8), in: context)
        addEntry(400_000, at: try makeDate(day: 2, month: 7), in: context)
        addEntry(900_000, at: try makeDate(day: 2, month: 6), in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)

        #expect(comparison.trailingSampleCount == 4)
        #expect(comparison.trailingAverage?.minorUnits == 250_000)
        #expect(comparison.insufficientHistoryMessage == nil)
    }

    @Test("Fewer than two comparable periods never fabricates an average")
    func insufficientHistory() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 10, month: 11)

        addEntry(100_000, at: try makeDate(day: 2, month: 10), in: context)
        try context.save()

        let onePeriod = try service.comparison(
            kind: .month,
            containing: current,
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(onePeriod.trailingSampleCount == 1)
        #expect(onePeriod.trailingAverage == nil)
        #expect(onePeriod.insufficientHistoryMessage == "Not enough data yet (1 of 2 periods)")

        addEntry(300_000, at: try makeDate(day: 2, month: 9), in: context)
        try context.save()

        let twoPeriods = try service.comparison(
            kind: .month,
            containing: current,
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(twoPeriods.trailingSampleCount == 2)
        #expect(twoPeriods.trailingAverage?.minorUnits == 200_000)
        #expect(twoPeriods.insufficientHistoryMessage == nil)
    }

    @Test("No history at all reports zero of two periods")
    func noHistory() throws {
        let (service, _) = try makeService()
        let comparison = try service.comparison(
            kind: .month,
            containing: try makeDate(day: 10, month: 11),
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(comparison.trailingSampleCount == 0)
        #expect(comparison.trailingAverage == nil)
        #expect(comparison.percentChange == nil)
        #expect(comparison.insufficientHistoryMessage == "Not enough data yet (0 of 2 periods)")
    }

    @Test("Percent change is nil when the previous total is zero")
    func percentChangeWithZeroPrevious() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 15, month: 11)

        addEntry(5_000, at: try makeDate(day: 2, month: 11), in: context)

        let zeroPrevious = try service.comparison(
            kind: .month,
            containing: current,
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(zeroPrevious.previousTotal.isZero)
        #expect(zeroPrevious.percentChange == nil)

        addEntry(2_000, at: try makeDate(day: 2, month: 10), in: context)
        try context.save()

        let withPrevious = try service.comparison(
            kind: .month,
            containing: current,
            displayCurrency: .kes,
            calendar: calendar
        )

        #expect(withPrevious.percentChange == 150.0)
    }

    // MARK: - Category deltas

    @Test("Category deltas include one-sided categories and sort by absolute difference")
    func categoryDeltas() throws {
        let (service, context) = try makeService()
        let food = makeCategory("Food", in: context)
        let rent = makeCategory("Rent", isFixed: true, in: context)
        let transport = makeCategory("Transport", in: context)
        let current = try makeDate(day: 15, month: 11)

        addEntry(300_000, at: try makeDate(day: 2, month: 11), category: food, in: context)
        addEntry(100_000, at: try makeDate(day: 3, month: 11), category: rent, in: context)
        addEntry(100_000, at: try makeDate(day: 2, month: 10), category: food, in: context)
        addEntry(200_000, at: try makeDate(day: 3, month: 10), category: transport, in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)
        let deltas = comparison.categoryDeltas

        #expect(deltas.count == 3)
        #expect(deltas.map(\.name) == ["Food", "Transport", "Rent"])
        #expect(deltas[0].current.minorUnits == 300_000)
        #expect(deltas[0].previous.minorUnits == 100_000)
        #expect(deltas[0].difference.minorUnits == 200_000)
        #expect(deltas[0].percentChange == 200.0)
        #expect(deltas[1].current.isZero)
        #expect(deltas[1].previous.minorUnits == 200_000)
        #expect(deltas[1].difference.minorUnits == -200_000)
        #expect(deltas[1].percentChange == -100.0)
        #expect(deltas[2].previous.isZero)
        #expect(deltas[2].percentChange == nil)
    }

    // MARK: - Merchants and small spends

    @Test("Top merchants group case-insensitively, skip empty payees and limit to five")
    func topMerchants() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 15, month: 11)
        let day = try makeDate(day: 2, month: 11)

        addEntry(100_000, at: day, payee: "KFC", in: context)
        addEntry(200_000, at: day, payee: "kfc ", in: context)
        addEntry(300_000, at: day, payee: " Kfc", in: context)
        addEntry(500_000, at: day, payee: "Naivas", in: context)
        addEntry(400_000, at: day, payee: "Uber", in: context)
        addEntry(300_000, at: day, payee: "Shell", in: context)
        addEntry(200_000, at: day, payee: "Java", in: context)
        addEntry(100_000, at: day, payee: "Tusky", in: context)
        addEntry(999_000, at: day, payee: "   ", in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)
        let merchants = comparison.topMerchants

        #expect(merchants.count == 5)
        #expect(merchants.first?.payee == "KFC")
        #expect(merchants.first?.count == 3)
        #expect(merchants.first?.total.minorUnits == 600_000)
        #expect(!merchants.contains { $0.payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(merchants.map(\.payee) == ["KFC", "Naivas", "Uber", "Shell", "Java"])
    }

    @Test("Small frequent spends use the default threshold and report repeated payees")
    func smallFrequentSpends() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 15, month: 11)
        let day = try makeDate(day: 2, month: 11)

        addEntry(40_000, at: day, payee: "Kiosk", in: context)
        addEntry(45_000, at: day, payee: "kiosk", in: context)
        addEntry(10_000, at: day, payee: "Kiosk", in: context)
        addEntry(50_000, at: day, payee: "Matatu", in: context)
        addEntry(30_000, at: day, payee: "matatu ", in: context)
        addEntry(60_000, at: day, payee: "Shop", in: context)

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)
        let small = try #require(comparison.smallFrequent)

        #expect(small.threshold.minorUnits == 50_000)
        #expect(small.count == 5)
        #expect(small.total.minorUnits == 175_000)
        #expect(small.topPayees.count == 2)
        #expect(small.topPayees[0].payee == "Kiosk")
        #expect(small.topPayees[0].count == 3)
        #expect(small.topPayees[0].total.minorUnits == 95_000)
        #expect(small.topPayees[1].payee == "Matatu")
        #expect(small.topPayees[1].count == 2)

        let explicit = try service.comparison(
            kind: .month,
            containing: current,
            displayCurrency: .kes,
            calendar: calendar,
            smallSpendThresholdMinor: 45_000
        )

        #expect(explicit.smallFrequent?.threshold.minorUnits == 45_000)
        #expect(explicit.smallFrequent?.count == 4)
        #expect(explicit.smallFrequent?.total.minorUnits == 125_000)
    }

    // MARK: - Balance drift

    @Test("Balance drift reports a mismatch and ignores a matching balance")
    func balanceDrift() throws {
        let (service, context) = try makeService()
        let current = try makeDate(day: 15, month: 11)

        let matching = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(matching)
        addEntry(
            100_000,
            at: try makeDate(day: 1, month: 10),
            kind: .openingBalance,
            account: matching,
            in: context
        )
        addEntry(
            10_000,
            at: try makeDate(day: 2, month: 11),
            account: matching,
            balanceAfterMinor: 90_000,
            in: context
        )
        addEntry(5_000, at: try makeDate(day: 3, month: 11), account: matching, in: context)

        let mismatch = Account(name: "Bank", kind: .bank)
        context.insert(mismatch)
        addEntry(
            200_000,
            at: try makeDate(day: 1, month: 10),
            kind: .openingBalance,
            account: mismatch,
            in: context
        )
        addEntry(
            10_000,
            at: try makeDate(day: 2, month: 11),
            account: mismatch,
            balanceAfterMinor: 195_000,
            in: context
        )
        addEntry(5_000, at: try makeDate(day: 3, month: 11), account: mismatch, in: context)

        let wallet = Account(name: "Wallet", kind: .cash)
        context.insert(wallet)
        addEntry(
            100_000,
            at: try makeDate(day: 1, month: 10),
            kind: .openingBalance,
            account: wallet,
            in: context
        )
        addEntry(
            1_000,
            at: try makeDate(day: 4, month: 11),
            account: wallet,
            balanceAfterMinor: 50_000,
            in: context
        )

        let archived = Account(name: "Old", kind: .bank)
        archived.isArchived = true
        context.insert(archived)
        addEntry(
            100_000,
            at: try makeDate(day: 1, month: 10),
            kind: .openingBalance,
            account: archived,
            in: context
        )
        addEntry(
            1_000,
            at: try makeDate(day: 5, month: 11),
            account: archived,
            balanceAfterMinor: 1,
            in: context
        )

        try context.save()

        let comparison = try service.comparison(
            kind: .month, containing: current, displayCurrency: .kes, calendar: calendar)
        let drift = comparison.balanceDrift

        #expect(drift.count == 2)
        #expect(drift[0].name == "Wallet")
        #expect(drift[0].reportedBalance.minorUnits == 50_000)
        #expect(drift[0].ledgerBalance.minorUnits == 99_000)
        #expect(drift[0].difference.minorUnits == 49_000)
        #expect(try drift[0].asOf == makeDate(day: 4, month: 11))

        #expect(drift[1].name == "Bank")
        #expect(drift[1].reportedBalance.minorUnits == 195_000)
        #expect(drift[1].ledgerBalance.minorUnits == 190_000)
        #expect(drift[1].difference.minorUnits == -5_000)
        #expect(!drift.contains { $0.name == "M-Pesa" })
        #expect(!drift.contains { $0.name == "Old" })
    }
}
