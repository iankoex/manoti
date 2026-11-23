//
//  NotificationPlannerTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels
@testable import AppServices

@Suite("NotificationPlanner")
struct NotificationPlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 1
        return calendar
    }

    private func makeDate(
        year: Int = 2026,
        month: Int = 11,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }

    private func preferences(
        master: Bool = true,
        daily: Bool = false,
        inbox: Bool = false,
        weekly: Bool = false,
        budget: Bool = false,
        large: Bool = false,
        hideAmounts: Bool = false,
        currencyCode: String = "KES",
        thresholdMinor: Int64 = 0
    ) -> NotificationPreferences {
        NotificationPreferences(
            masterEnabled: master,
            dailyReminderEnabled: daily,
            inboxReminderEnabled: inbox,
            weeklySummaryEnabled: weekly,
            budgetAlertsEnabled: budget,
            largeTransactionAlertsEnabled: large,
            hideAmounts: hideAmounts,
            displayCurrency: CurrencyCatalog.currency(for: currencyCode),
            largeTransactionThresholdMinor: thresholdMinor
        )
    }

    private func money(_ minorUnits: Int64, _ code: String = "KES") -> Money {
        Money(minorUnits: minorUnits, currency: CurrencyCatalog.currency(for: code))
    }

    private func plan(
        now: Date,
        hasLoggedToday: Bool = true,
        inboxCount: Int = 0,
        weekSpend: Money? = nil,
        budgetRows: [NotificationBudgetRow] = [],
        largeEntry: NotificationLargeEntry? = nil,
        preferences: NotificationPreferences
    ) -> [PlannedNotification] {
        NotificationPlanner.plan(
            now: now,
            calendar: calendar,
            hasLoggedToday: hasLoggedToday,
            inboxCount: inboxCount,
            weekSpend: weekSpend ?? money(0),
            budgetRows: budgetRows,
            largeEntry: largeEntry,
            preferences: preferences
        )
    }

    // MARK: - Master

    @Test("Notifications are empty when the master switch is off")
    func masterOff() throws {
        let now = try makeDate(day: 22, hour: 12)
        let row = NotificationBudgetRow(
            envelopeID: UUID(),
            categoryName: "Food",
            spentMinor: 9_000,
            limitMinor: 10_000,
            periodStart: try makeDate(day: 1, hour: 0)
        )
        let entry = NotificationLargeEntry(
            entryID: UUID(),
            amountMinor: 90_000,
            currencyCode: "KES",
            payee: "Shop",
            occurredAt: now
        )

        let planned = plan(
            now: now,
            hasLoggedToday: false,
            inboxCount: 3,
            weekSpend: money(50_000),
            budgetRows: [row],
            largeEntry: entry,
            preferences: preferences(
                master: false,
                daily: true,
                inbox: true,
                weekly: true,
                budget: true,
                large: true,
                thresholdMinor: 1_000
            )
        )

        #expect(planned.isEmpty)
    }

    // MARK: - Daily

    @Test("The daily reminder uses the next 20:00 in the future")
    func dailyNextFire() throws {
        let evening = try makeDate(day: 22, hour: 19, minute: 30)
        let after = try makeDate(day: 22, hour: 21)

        let early = try #require(
            plan(now: evening, hasLoggedToday: false, preferences: preferences(daily: true)).first
        )
        let late = try #require(
            plan(now: after, hasLoggedToday: false, preferences: preferences(daily: true)).first
        )

        #expect(early.identifier == "manoti.daily")
        #expect(early.kind == .dailyReminder)
        #expect(early.fireDate == (try makeDate(day: 22, hour: 20)))
        #expect(late.fireDate == (try makeDate(day: 23, hour: 20)))
    }

    @Test("The daily reminder is skipped when something was logged today")
    func dailySkipsLoggedDay() throws {
        let now = try makeDate(day: 22, hour: 12)

        let planned = plan(now: now, hasLoggedToday: true, preferences: preferences(daily: true))

        #expect(planned.isEmpty)
    }

    // MARK: - Inbox

    @Test("The Inbox reminder uses the next 19:00 and needs pending messages")
    func inboxReminder() throws {
        let now = try makeDate(day: 22, hour: 18)
        let after = try makeDate(day: 22, hour: 20)

        let planned = try #require(
            plan(now: now, inboxCount: 2, preferences: preferences(inbox: true)).first
        )
        let later = try #require(
            plan(now: after, inboxCount: 1, preferences: preferences(inbox: true)).first
        )

        #expect(planned.identifier == "manoti.inbox")
        #expect(planned.kind == .inboxReminder)
        #expect(planned.fireDate == (try makeDate(day: 22, hour: 19)))
        #expect(planned.body.contains("2"))
        #expect(later.fireDate == (try makeDate(day: 23, hour: 19)))
    }

    @Test("An empty Inbox schedules no reminder")
    func inboxReminderSkippedWhenEmpty() throws {
        let now = try makeDate(day: 22, hour: 18)

        #expect(plan(now: now, inboxCount: 0, preferences: preferences(inbox: true)).isEmpty)
    }

    // MARK: - Weekly

    @Test("The weekly summary targets the last day of the user's week")
    func weeklyNextFire() throws {
        // This calendar starts on Sunday, so the last day is Saturday 28 November.
        let sundayNoon = try makeDate(day: 22, hour: 12)
        let sundayEvening = try makeDate(day: 22, hour: 19)

        let sameWeek = try #require(plan(now: sundayNoon, preferences: preferences(weekly: true)).first)
        let laterThatWeek = try #require(plan(now: sundayEvening, preferences: preferences(weekly: true)).first)

        #expect(sameWeek.identifier == "manoti.weekly")
        #expect(sameWeek.fireDate == (try makeDate(day: 28, hour: 18)))
        #expect(laterThatWeek.fireDate == (try makeDate(day: 28, hour: 18)))
    }

    @Test("The weekly summary stays generic so stale text cannot mislead")
    func weeklySummaryText() throws {
        let now = try makeDate(day: 22, hour: 12)
        let spend = money(1_234_000)

        let visible = try #require(
            plan(now: now, weekSpend: spend, preferences: preferences(weekly: true)).first
        )
        let hidden = try #require(
            plan(
                now: now,
                weekSpend: spend,
                preferences: preferences(weekly: true, hideAmounts: true)
            ).first
        )

        #expect(visible.body == "Open Manoti to review your week.")
        #expect(hidden.body == "Open Manoti to review your week.")
        #expect(!visible.body.contains("KES"))
    }

    // MARK: - Budget

    private func budgetRow(
        id: UUID = UUID(),
        name: String = "Food",
        spent: Int64,
        limit: Int64 = 10_000,
        lastAlertPercent: Int = 0
    ) throws -> NotificationBudgetRow {
        NotificationBudgetRow(
            envelopeID: id,
            categoryName: name,
            spentMinor: spent,
            limitMinor: limit,
            periodStart: try makeDate(day: 1, hour: 0),
            lastAlertPercent: lastAlertPercent
        )
    }

    @Test("A budget alerts once at 80% and at 100%")
    func budgetThresholds() throws {
        let now = try makeDate(day: 22, hour: 12)
        let warning = try #require(
            plan(
                now: now,
                budgetRows: [try budgetRow(spent: 8_000)],
                preferences: preferences(budget: true)
            ).first
        )
        let over = try #require(
            plan(
                now: now,
                budgetRows: [try budgetRow(spent: 10_000)],
                preferences: preferences(budget: true)
            ).first
        )

        #expect(warning.kind == .budgetWarning)
        #expect(warning.identifier.hasPrefix("manoti.budget."))
        #expect(warning.identifier.hasSuffix(".80"))
        #expect(warning.body.contains("80%"))
        #expect(warning.fireDate == now.addingTimeInterval(NotificationPlanner.immediateDelay))

        #expect(over.kind == .budgetOver)
        #expect(over.identifier.hasSuffix(".100"))
    }

    @Test("A budget below 80% or with a zero limit schedules nothing")
    func budgetBelowThreshold() throws {
        let now = try makeDate(day: 22, hour: 12)

        #expect(
            plan(
                now: now,
                budgetRows: [try budgetRow(spent: 7_999)],
                preferences: preferences(budget: true)
            ).isEmpty
        )
        #expect(
            plan(
                now: now,
                budgetRows: [try budgetRow(spent: 5_000, limit: 0)],
                preferences: preferences(budget: true)
            ).isEmpty
        )
    }

    @Test("An already-alerted threshold is suppressed, but crossing the next one is not")
    func budgetSuppression() throws {
        let now = try makeDate(day: 22, hour: 12)

        #expect(
            plan(
                now: now,
                budgetRows: [try budgetRow(spent: 8_500, lastAlertPercent: 80)],
                preferences: preferences(budget: true)
            ).isEmpty
        )

        let over = try #require(
            plan(
                now: now,
                budgetRows: [try budgetRow(spent: 10_500, lastAlertPercent: 80)],
                preferences: preferences(budget: true)
            ).first
        )

        #expect(over.kind == .budgetOver)
        #expect(over.identifier.hasSuffix(".100"))
    }

    @Test("Budget alerts are ordered by envelope and omit amounts when hidden")
    func budgetOrderAndRedaction() throws {
        let now = try makeDate(day: 22, hour: 12)
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let rows = [
            try budgetRow(id: secondID, name: "Travel", spent: 9_000),
            try budgetRow(id: firstID, name: "Food", spent: 9_000),
        ]

        let planned = plan(now: now, budgetRows: rows, preferences: preferences(budget: true))
        let hidden = try #require(
            plan(
                now: now,
                budgetRows: rows,
                preferences: preferences(budget: true, hideAmounts: true)
            ).first
        )

        #expect(
            planned.map(\.identifier) == [
                "manoti.budget.\(firstID.uuidString).80",
                "manoti.budget.\(secondID.uuidString).80",
            ])
        #expect(!hidden.body.contains("KES"))
        #expect(hidden.body.contains("90%"))
    }

    // MARK: - Large transactions

    private func largeEntry(
        id: UUID = UUID(),
        amount: Int64 = 5_000,
        payee: String = "Furniture"
    ) -> NotificationLargeEntry {
        NotificationLargeEntry(
            entryID: id,
            amountMinor: amount,
            currencyCode: "KES",
            payee: payee,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @Test("A large transaction alerts at the threshold, not below it")
    func largeThreshold() throws {
        let now = try makeDate(day: 22, hour: 12)
        let entry = largeEntry()
        let planned = try #require(
            plan(
                now: now,
                largeEntry: entry,
                preferences: preferences(large: true, thresholdMinor: 5_000)
            ).first
        )

        #expect(planned.identifier == "manoti.large.\(entry.entryID.uuidString)")
        #expect(planned.kind == .largeTransaction)
        #expect(planned.body.contains("Furniture"))
        #expect(planned.body.contains("KES"))

        #expect(
            plan(
                now: now,
                largeEntry: largeEntry(amount: 4_999),
                preferences: preferences(large: true, thresholdMinor: 5_000)
            ).isEmpty
        )
        #expect(
            plan(
                now: now,
                largeEntry: entry,
                preferences: preferences(large: true, thresholdMinor: 0)
            ).isEmpty
        )
        #expect(
            plan(
                now: now,
                largeEntry: entry,
                preferences: preferences(large: false, thresholdMinor: 1_000)
            ).isEmpty
        )
    }

    @Test("A large transaction omits the amount in privacy mode")
    func largeRedaction() throws {
        let now = try makeDate(day: 22, hour: 12)
        let planned = try #require(
            plan(
                now: now,
                largeEntry: largeEntry(),
                preferences: preferences(large: true, hideAmounts: true, thresholdMinor: 1_000)
            ).first
        )

        #expect(planned.body.contains("Furniture"))
        #expect(!planned.body.contains("KES"))
    }

    @Test("The full plan has deterministic identifiers and order")
    func deterministicPlan() throws {
        let now = try makeDate(day: 22, hour: 12)
        let envelopeID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA"))
        let entry = largeEntry(id: try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")))
        let all = preferences(
            daily: true,
            inbox: true,
            weekly: true,
            budget: true,
            large: true,
            thresholdMinor: 1_000
        )

        let first = plan(
            now: now,
            hasLoggedToday: false,
            inboxCount: 1,
            weekSpend: money(1_000),
            budgetRows: [try budgetRow(id: envelopeID, spent: 9_000)],
            largeEntry: entry,
            preferences: all
        )
        let second = plan(
            now: now,
            hasLoggedToday: false,
            inboxCount: 1,
            weekSpend: money(1_000),
            budgetRows: [try budgetRow(id: envelopeID, spent: 9_000)],
            largeEntry: entry,
            preferences: all
        )

        #expect(first.map(\.identifier) == second.map(\.identifier))
        #expect(
            first.map(\.identifier) == [
                "manoti.daily",
                "manoti.inbox",
                "manoti.weekly",
                "manoti.budget.\(envelopeID.uuidString).80",
                "manoti.large.\(entry.entryID.uuidString)",
            ])
    }
}
