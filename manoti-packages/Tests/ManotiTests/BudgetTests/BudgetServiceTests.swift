//
//  BudgetServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("BudgetService")
struct BudgetServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeService() throws -> (BudgetService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (BudgetService(context: context, calendar: calendar), context)
    }

    private func makeDate(day: Int, month: Int = 11, year: Int = 2026, hour: Int = 12) throws -> Date {
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
        sortIndex: Int = 0,
        in context: ModelContext
    ) -> SpendingCategory {
        let category = SpendingCategory(
            name: name,
            symbolName: "circle",
            colorHex: "#FF9500",
            isFixed: isFixed,
            sortIndex: sortIndex
        )
        context.insert(category)
        return category
    }

    @discardableResult
    private func addEntry(
        kind: LedgerEntryKind = .expense,
        amountMinor: Int64,
        category: SpendingCategory? = nil,
        at occurredAt: Date,
        status: LedgerEntryStatus = .confirmed,
        isSoftDeleted: Bool = false,
        currencyCode: String = "KES",
        in context: ModelContext
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            kind: kind,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            occurredAt: occurredAt
        )
        entry.attachSingleLine(category: category, in: context)
        entry.status = status
        entry.isSoftDeleted = isSoftDeleted
        context.insert(entry)
        return entry
    }

    // MARK: - Periods

    @Test("The current period is created once and reused")
    func periodIdempotency() throws {
        let (service, context) = try makeService()

        let first = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let second = try service.currentPeriod(kind: .month, containing: try makeDate(day: 27), calendar: calendar)

        #expect(first.id == second.id)
        #expect(first.startDate == (try makeDate(day: 1, hour: 0)))
        #expect(first.endDate == (try makeDate(day: 1, month: 12, hour: 0)))

        let periods = try context.fetch(FetchDescriptor<BudgetPeriod>())
        #expect(periods.count == 1)
    }

    @Test("Weeks follow the calendar's first weekday and stay distinct from months")
    func weekPeriods() throws {
        let (service, context) = try makeService()

        let first = try service.currentPeriod(kind: .week, containing: try makeDate(day: 5), calendar: calendar)
        let second = try service.currentPeriod(kind: .week, containing: try makeDate(day: 6), calendar: calendar)
        let month = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)

        #expect(first.id == second.id)
        #expect(first.id != month.id)
        #expect(first.startDate == (try makeDate(day: 2, hour: 0)))
        #expect(first.endDate == (try makeDate(day: 9, hour: 0)))

        let periods = try context.fetch(FetchDescriptor<BudgetPeriod>())
        #expect(periods.count == 2)
    }

    // MARK: - Envelopes

    @Test("Setting an envelope twice updates the same row")
    func envelopeUpsert() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)

        let first = try service.setEnvelope(
            category: food,
            limitMinor: 50_000,
            rolloverEnabled: false,
            in: period
        )
        let second = try service.setEnvelope(
            category: food,
            limitMinor: 75_000,
            rolloverEnabled: true,
            in: period
        )

        #expect(first.id == second.id)
        #expect(second.limitMinor == 75_000)
        #expect(second.rolloverEnabled)
        #expect(try service.envelopes(for: period).count == 1)

        let envelopes = try context.fetch(FetchDescriptor<Envelope>())
        #expect(envelopes.count == 1)
    }

    @Test("An archived category and a negative limit are rejected")
    func envelopeValidation() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let archived = makeCategory("Old", in: context)
        archived.isArchived = true

        #expect(throws: BudgetError.archivedCategory) {
            try service.setEnvelope(category: archived, limitMinor: 10_000, rolloverEnabled: false, in: period)
        }

        let food = makeCategory("Food", in: context)
        #expect(throws: BudgetError.invalidLimit) {
            try service.setEnvelope(category: food, limitMinor: -1, rolloverEnabled: false, in: period)
        }
    }

    // MARK: - Actuals

    @Test("Only confirmed expenses inside the period count")
    func actualsOnlyConfirmedExpenses() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)

        addEntry(amountMinor: 12_000, category: food, at: try makeDate(day: 5), in: context)
        addEntry(kind: .income, amountMinor: 90_000, category: food, at: try makeDate(day: 5), in: context)
        addEntry(kind: .adjustment, amountMinor: 5_000, category: food, at: try makeDate(day: 5), in: context)
        addEntry(amountMinor: 7_000, category: food, at: try makeDate(day: 6), status: .needsReview, in: context)
        addEntry(amountMinor: 8_000, category: food, at: try makeDate(day: 7), status: .ignored, in: context)
        addEntry(amountMinor: 9_000, category: food, at: try makeDate(day: 8), isSoftDeleted: true, in: context)
        addEntry(amountMinor: 11_000, category: food, at: try makeDate(day: 31, month: 10), in: context)
        addEntry(amountMinor: 13_000, category: food, at: try makeDate(day: 1, month: 12), in: context)

        #expect(try service.actualMinor(for: food, in: period) == 12_000)
    }

    @Test("Transfers, loans and investments never count as budget spending")
    func linkedCashIsExcluded() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)
        try service.setEnvelope(category: food, limitMinor: 50_000, rolloverEnabled: false, in: period)

        let transfer = Transfer(occurredAt: try makeDate(day: 4))
        context.insert(transfer)
        let transferLeg = addEntry(amountMinor: 20_000, category: food, at: try makeDate(day: 4), in: context)
        transferLeg.transfer = transfer

        let loan = Loan(direction: .borrowed, counterparty: "Brian", principalMinor: 100_000)
        context.insert(loan)
        let loanLeg = addEntry(amountMinor: 30_000, category: food, at: try makeDate(day: 5), in: context)
        loanLeg.loan = loan

        let investment = Investment(type: .treasuryBond)
        context.insert(investment)
        let cashFlow = InvestmentCashFlow(kind: .purchase, date: try makeDate(day: 6))
        cashFlow.investment = investment
        context.insert(cashFlow)
        let investmentLeg = addEntry(amountMinor: 40_000, category: food, at: try makeDate(day: 6), in: context)
        investmentLeg.investmentCashFlow = cashFlow

        addEntry(amountMinor: 5_000, category: food, at: try makeDate(day: 7), in: context)

        let summary = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(try service.actualMinor(for: food, in: period) == 5_000)
        #expect(summary.totalSpent.minorUnits == 5_000)
        #expect(summary.unbudgeted.minorUnits == 0)
    }

    @Test("Actuals convert at each entry's date")
    func historicalRates() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)

        context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 130_000_000,
                asOf: try makeDate(day: 2, hour: 0)
            )
        )
        context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 140_000_000,
                asOf: try makeDate(day: 16, hour: 0)
            )
        )
        try context.save()

        addEntry(amountMinor: 10_000, category: food, at: try makeDate(day: 2), currencyCode: "USD", in: context)
        addEntry(amountMinor: 10_000, category: food, at: try makeDate(day: 16), currencyCode: "USD", in: context)

        // USD 100 at 130 plus USD 100 at 140.
        #expect(try service.actualMinor(for: food, in: period) == 2_700_000)
    }

    @Test("An envelope limit converts from its stored currency")
    func limitConversion() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)

        context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 130_000_000,
                asOf: try makeDate(day: 1, hour: 0)
            )
        )
        let envelope = Envelope(
            period: period,
            category: food,
            limitMinor: 50_000_000,
            currencyCode: "KES"
        )
        context.insert(envelope)
        try context.save()

        let summary = try service.summary(
            for: period,
            displayCurrency: .usd,
            now: try makeDate(day: 15)
        )
        // 50,000 KES at the inverted 1e-6 scaled rate.
        #expect(summary.totalLimit.minorUnits == 384_600)
        #expect(summary.envelopes.first?.limit.minorUnits == 384_600)
    }

    @Test("Editing an envelope keeps the currency its limit was entered in")
    func envelopeCurrencyPreserved() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)
        let envelope = try service.setEnvelope(
            category: food, limitMinor: 10_000, rolloverEnabled: false, in: period)
        envelope.currencyCode = "UGX"

        try service.setEnvelope(category: food, limitMinor: 10_000, rolloverEnabled: false, in: period)
        #expect(envelope.currencyCode == "UGX")
    }

    @Test("Duplicate envelope rows for one category are folded, not double-counted")
    func duplicateEnvelopes() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)

        let older = Envelope(period: period, category: food, limitMinor: 10_000)
        older.createdAt = try makeDate(day: 1)
        context.insert(older)
        let newer = Envelope(period: period, category: food, limitMinor: 20_000)
        newer.createdAt = try makeDate(day: 2)
        context.insert(newer)
        addEntry(amountMinor: 5_000, category: food, at: try makeDate(day: 3), in: context)
        try context.save()

        let summary = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(summary.totalLimit.minorUnits == 20_000)
        #expect(summary.totalSpent.minorUnits == 5_000)
        #expect(summary.remaining.minorUnits == 15_000)
        #expect(summary.envelopes.count == 1)
    }

    @Test("Fixed and variable envelopes are totalled separately")
    func fixedAndVariableTotals() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let rent = makeCategory("Rent", isFixed: true, sortIndex: 0, in: context)
        let food = makeCategory("Food", sortIndex: 1, in: context)

        try service.setEnvelope(category: rent, limitMinor: 100_000, rolloverEnabled: false, in: period)
        try service.setEnvelope(category: food, limitMinor: 50_000, rolloverEnabled: false, in: period)

        addEntry(amountMinor: 100_000, category: rent, at: try makeDate(day: 2), in: context)
        addEntry(amountMinor: 20_000, category: food, at: try makeDate(day: 3), in: context)

        let summary = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))

        #expect(summary.totalLimit.minorUnits == 150_000)
        #expect(summary.totalSpent.minorUnits == 120_000)
        #expect(summary.remaining.minorUnits == 30_000)
        #expect(summary.fixedLimit.minorUnits == 100_000)
        #expect(summary.fixedSpent.minorUnits == 100_000)
        #expect(summary.variableLimit.minorUnits == 50_000)
        #expect(summary.variableSpent.minorUnits == 20_000)
        #expect(summary.envelopes.map(\.isFixed) == [true, false])
    }

    // MARK: - Pacing

    @Test("Pacing projects from day one and from mid-period")
    func pacing() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)
        try service.setEnvelope(category: food, limitMinor: 300_000, rolloverEnabled: false, in: period)

        addEntry(amountMinor: 10_000, category: food, at: try makeDate(day: 1), in: context)

        let firstDay = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 1))
        #expect(firstDay.totalDays == 30)
        #expect(firstDay.elapsedDays == 1)
        #expect(firstDay.daysRemaining == 30)
        #expect(firstDay.projectedSpend.minorUnits == 300_000)

        addEntry(amountMinor: 140_000, category: food, at: try makeDate(day: 14), in: context)

        let midPeriod = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(midPeriod.elapsedDays == 15)
        #expect(midPeriod.daysRemaining == 16)
        #expect(midPeriod.totalSpent.minorUnits == 150_000)
        #expect(midPeriod.projectedSpend.minorUnits == 300_000)

        // A period that has not started must not divide by zero.
        let future = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 1, month: 10))
        #expect(future.elapsedDays == 0)
        #expect(future.projectedSpend.isZero)
    }

    // MARK: - Rollover

    @Test("Positive rollover carries the prior remaining once")
    func positiveRollover() throws {
        let (service, context) = try makeService()
        let food = makeCategory("Food", in: context)

        let october = try service.currentPeriod(
            kind: .month, containing: try makeDate(day: 15, month: 10), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: october)
        addEntry(amountMinor: 60_000, category: food, at: try makeDate(day: 10, month: 10), in: context)

        let november = try service.currentPeriod(kind: .month, containing: try makeDate(day: 15), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: november)
        addEntry(amountMinor: 30_000, category: food, at: try makeDate(day: 10), in: context)

        let summary = try service.summary(for: november, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(summary.rollover.minorUnits == 40_000)
        #expect(summary.envelopes.first?.rollover.minorUnits == 40_000)
        #expect(summary.envelopes.first?.remaining.minorUnits == 110_000)

        let repeated = try service.summary(for: november, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(repeated.rollover.minorUnits == 40_000)
    }

    @Test("Negative rollover reduces the next period")
    func negativeRollover() throws {
        let (service, context) = try makeService()
        let food = makeCategory("Food", in: context)

        let october = try service.currentPeriod(
            kind: .month, containing: try makeDate(day: 15, month: 10), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: october)
        addEntry(amountMinor: 130_000, category: food, at: try makeDate(day: 10, month: 10), in: context)

        let november = try service.currentPeriod(kind: .month, containing: try makeDate(day: 15), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: november)
        addEntry(amountMinor: 20_000, category: food, at: try makeDate(day: 10), in: context)

        let summary = try service.summary(for: november, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(summary.rollover.minorUnits == -30_000)
        #expect(summary.envelopes.first?.remaining.minorUnits == 50_000)
    }

    @Test("Rollover chains through earlier periods")
    func chainedRollover() throws {
        let (service, context) = try makeService()
        let food = makeCategory("Food", in: context)

        let september = try service.currentPeriod(
            kind: .month, containing: try makeDate(day: 15, month: 9), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: september)
        addEntry(amountMinor: 70_000, category: food, at: try makeDate(day: 10, month: 9), in: context)

        let october = try service.currentPeriod(
            kind: .month, containing: try makeDate(day: 15, month: 10), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: october)
        addEntry(amountMinor: 30_000, category: food, at: try makeDate(day: 10, month: 10), in: context)

        let november = try service.currentPeriod(kind: .month, containing: try makeDate(day: 15), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: november)

        // September left 30,000, so October finished with 100,000 and November carries that.
        let summary = try service.summary(for: november, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(summary.rollover.minorUnits == 100_000)
        #expect(summary.envelopes.first?.remaining.minorUnits == 200_000)
    }

    @Test("Disabled rollover carries nothing")
    func disabledRollover() throws {
        let (service, context) = try makeService()
        let food = makeCategory("Food", in: context)

        let october = try service.currentPeriod(
            kind: .month, containing: try makeDate(day: 15, month: 10), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: true, in: october)
        addEntry(amountMinor: 60_000, category: food, at: try makeDate(day: 10, month: 10), in: context)

        let november = try service.currentPeriod(kind: .month, containing: try makeDate(day: 15), calendar: calendar)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: false, in: november)
        addEntry(amountMinor: 30_000, category: food, at: try makeDate(day: 10), in: context)

        let summary = try service.summary(for: november, displayCurrency: .kes, now: try makeDate(day: 15))
        #expect(summary.rollover.isZero)
        #expect(summary.envelopes.first?.remaining.minorUnits == 70_000)
    }

    // MARK: - Unbudgeted

    @Test("Spending outside every envelope is reported as unbudgeted")
    func unbudgetedSpending() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)
        let transport = makeCategory("Transport", sortIndex: 1, in: context)

        try service.setEnvelope(category: food, limitMinor: 50_000, rolloverEnabled: false, in: period)
        addEntry(amountMinor: 20_000, category: food, at: try makeDate(day: 2), in: context)
        addEntry(amountMinor: 15_000, category: transport, at: try makeDate(day: 3), in: context)
        addEntry(amountMinor: 5_000, category: nil, at: try makeDate(day: 4), in: context)

        let summary = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))

        #expect(summary.totalSpent.minorUnits == 20_000)
        #expect(summary.unbudgeted.minorUnits == 20_000)
        #expect(summary.totalOutflow.minorUnits == 40_000)
        #expect(summary.remaining.minorUnits == 30_000)
    }

    // MARK: - Safe to spend

    @Test("Safe to spend excludes fixed envelopes")
    func safeToSpendExcludesFixed() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 1), calendar: calendar)
        let rent = makeCategory("Rent", isFixed: true, sortIndex: 0, in: context)
        let food = makeCategory("Food", sortIndex: 1, in: context)
        let fun = makeCategory("Fun", sortIndex: 2, in: context)

        try service.setEnvelope(category: rent, limitMinor: 100_000, rolloverEnabled: false, in: period)
        try service.setEnvelope(category: food, limitMinor: 60_000, rolloverEnabled: false, in: period)
        try service.setEnvelope(category: fun, limitMinor: 0, rolloverEnabled: false, in: period)

        addEntry(amountMinor: 20_000, category: rent, at: try makeDate(day: 1), in: context)

        let safe = try service.safeToSpend(for: period, displayCurrency: .kes, now: try makeDate(day: 1))
        #expect(safe.daysRemaining == 30)
        #expect(safe.discretionaryRemaining.minorUnits == 60_000)
        #expect(safe.amount.minorUnits == 2_000)

        // Overspending the flexible envelope clamps the daily amount at zero.
        addEntry(amountMinor: 90_000, category: food, at: try makeDate(day: 2), in: context)
        let overspent = try service.safeToSpend(for: period, displayCurrency: .kes, now: try makeDate(day: 2))
        #expect(overspent.discretionaryRemaining.isZero)
        #expect(overspent.amount.isZero)
    }

    @Test("Safe to spend never divides by zero")
    func safeToSpendZeroDayGuard() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 1), calendar: calendar)
        let food = makeCategory("Food", in: context)
        try service.setEnvelope(category: food, limitMinor: 60_000, rolloverEnabled: false, in: period)

        let ended = try service.safeToSpend(for: period, displayCurrency: .kes, now: try makeDate(day: 5, month: 12))
        #expect(ended.daysRemaining == 0)
        #expect(ended.amount.isZero)
        #expect(ended.discretionaryRemaining.minorUnits == 60_000)

        let beforeStart = try service.safeToSpend(
            for: period, displayCurrency: .kes, now: try makeDate(day: 1, month: 10))
        #expect(beforeStart.daysRemaining == 30)
        #expect(beforeStart.amount.minorUnits == 2_000)
    }

    // MARK: - FX

    @Test("A missing rate is marked and shown 1:1 in major units")
    func missingRate() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: false, in: period)

        addEntry(amountMinor: 10_000, category: food, at: try makeDate(day: 5), currencyCode: "USD", in: context)

        let summary = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))

        #expect(summary.missingRates == ["USD"])
        #expect(summary.envelopes.first?.missingRates == ["USD"])
        // USD 100.00 becomes KES 100.00 (10,000 minor units), never raw minor units.
        #expect(summary.totalSpent.minorUnits == 10_000)
        #expect(try service.actualMinor(for: food, in: period) == 10_000)
    }

    @Test("Same-currency spending reports no missing rate when none are stored")
    func sameCurrencyNeedsNoRate() throws {
        let (service, context) = try makeService()
        let period = try service.currentPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: context)
        try service.setEnvelope(category: food, limitMinor: 100_000, rolloverEnabled: false, in: period)

        addEntry(amountMinor: 25_000, category: food, at: try makeDate(day: 5), currencyCode: "KES", in: context)

        let summary = try service.summary(for: period, displayCurrency: .kes, now: try makeDate(day: 15))

        #expect(try context.fetch(FetchDescriptor<ExchangeRateRecord>()).isEmpty)
        #expect(summary.missingRates.isEmpty)
        #expect(summary.envelopes.first?.missingRates == [])
        #expect(summary.totalSpent.minorUnits == 25_000)
        #expect(summary.envelopes.first?.spent.minorUnits == 25_000)
        #expect(try service.actualMinor(for: food, in: period) == 25_000)
    }
}
