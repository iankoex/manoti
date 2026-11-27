//
//  BudgetModelTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels

@MainActor
@Suite("Budget models")
struct BudgetModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
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

    @Test("A month and a week resolve to calendar-aligned intervals")
    func periodIntervals() throws {
        let november = try makeDate(day: 5)

        let month = BudgetPeriodKind.month.dateInterval(containing: november, calendar: calendar)
        #expect(month.start == (try makeDate(day: 1, hour: 0)))
        #expect(month.end == (try makeDate(day: 1, month: 12, hour: 0)))

        // 5 November 2026 is a Thursday; the Monday-start week begins on the 2nd.
        let week = BudgetPeriodKind.week.dateInterval(containing: november, calendar: calendar)
        #expect(week.start == (try makeDate(day: 2, hour: 0)))
        #expect(week.end == (try makeDate(day: 9, hour: 0)))
    }

    @Test("The schema stores every budget model")
    func schemaContainsBudgetModels() {
        #expect(ManotiSchema.models.count == 29)
        #expect(ManotiSchema.models.contains { $0 == BudgetPeriod.self })
        #expect(ManotiSchema.models.contains { $0 == Envelope.self })
        #expect(ManotiSchema.models.contains { $0 == SinkingFund.self })
        #expect(ManotiSchema.models.contains { $0 == SinkingFundContribution.self })
        #expect(ManotiSchema.models.contains { $0 == Goal.self })
        #expect(ManotiSchema.models.contains { $0 == BudgetAlert.self })
    }

    @Test("Budget rows round-trip with their inverse relationships")
    func roundTrip() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        let category = SpendingCategory(name: "Food", symbolName: "fork.knife", colorHex: "#FF9500")
        let period = BudgetPeriod(kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        context.insert(account)
        context.insert(category)
        context.insert(period)

        let envelope = Envelope(period: period, category: category, limitMinor: 50_000)
        let alert = BudgetAlert(envelope: envelope, thresholdPercent: 80)
        let fund = SinkingFund(
            name: "Car service",
            targetMinor: 300_000,
            category: category,
            account: account
        )
        let contribution = SinkingFundContribution(fund: fund, amountMinor: 20_000, account: account)
        let goal = Goal(name: "Emergency fund", targetMinor: 1_000_000, account: account)
        context.insert(envelope)
        context.insert(alert)
        context.insert(fund)
        context.insert(contribution)
        context.insert(goal)

        try context.save()

        #expect(period.envelopes?.count == 1)
        #expect(category.budgetEnvelopes?.count == 1)
        #expect(envelope.alerts?.count == 1)
        #expect(fund.contributions?.count == 1)
        #expect(category.sinkingFunds?.count == 1)
        #expect(account.sinkingFunds?.count == 1)
        #expect(account.sinkingFundContributions?.count == 1)
        #expect(account.goals?.count == 1)
        #expect(fund.fundedMinor == 20_000)
        #expect(goal.account?.id == account.id)

        let periods = try context.fetch(FetchDescriptor<BudgetPeriod>())
        let envelopes = try context.fetch(FetchDescriptor<Envelope>())
        let alerts = try context.fetch(FetchDescriptor<BudgetAlert>())
        #expect(periods.count == 1)
        #expect(envelopes.count == 1)
        #expect(alerts.count == 1)
        #expect(envelopes.first?.category?.name == "Food")
    }

    @Test("A period's kind falls back safely when the raw value is unknown")
    func periodKindFallback() throws {
        let period = BudgetPeriod(kind: .week, containing: try makeDate(day: 5), calendar: calendar)
        #expect(period.kind == .week)

        period.kindRaw = "quarter"
        #expect(period.kind == .month)
    }
}
