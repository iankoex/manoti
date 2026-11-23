//
//  ReconcileFormattingTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels
@testable import ReconcileFeature

@MainActor
@Suite("Reconcile formatting")
struct ReconcileFormattingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeDate(
        year: Int = 2026,
        month: Int = 11,
        day: Int,
        hour: Int = 12,
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

    @Test("Today starts at midnight and ends at the current moment")
    func todayInterval() throws {
        let now = try makeDate(day: 22, hour: 18, minute: 30)
        let interval = ReconcilePeriodPreset.today.dateInterval(calendar: calendar, now: now)

        #expect(interval.start == (try makeDate(day: 22, hour: 0)))
        #expect(interval.end == now)
        #expect(interval.duration == 18.5 * 60 * 60)
    }

    @Test("Last 7 days starts at the day boundary seven days back, across a month boundary")
    func lastSevenDaysInterval() throws {
        let now = try makeDate(month: 12, day: 3, hour: 9, minute: 30)
        let interval = ReconcilePeriodPreset.lastSevenDays.dateInterval(calendar: calendar, now: now)

        #expect(interval.start == (try makeDate(month: 11, day: 26, hour: 0)))
        #expect(interval.end == now)
    }

    @Test("Bucket titles carry their count and use entries for the ledger bucket")
    func bucketTitles() {
        #expect(ReconcileFormatting.bucketTitle(for: .missing, count: 2) == "Missing from app (2)")
        #expect(ReconcileFormatting.bucketTitle(for: .matched, count: 1) == "Matched (1)")
        #expect(ReconcileFormatting.bucketTitle(for: .notInMessages, count: 1) == "Not in messages (1 entry)")
        #expect(ReconcileFormatting.bucketTitle(for: .notInMessages, count: 2) == "Not in messages (2 entries)")
        #expect(ReconcileFormatting.bucketTitle(for: .possible, count: 1) == "Possible (1)")
    }

    @Test("A single-day session shows one date, not the same date twice")
    func singleDaySubtitle() throws {
        let start = try makeDate(day: 22, hour: 0)
        let end = try makeDate(day: 22, hour: 18, minute: 30)

        #expect(
            ReconcileFormatting.sessionSubtitle(
                periodStart: start,
                periodEnd: end,
                messageCount: 0,
                calendar: calendar
            ) == "22 Nov 2026 · 0 messages"
        )
    }

    @Test("A half-open midnight end belongs to the previous day")
    func halfOpenEndDay() throws {
        let start = try makeDate(day: 16, hour: 0)
        let end = try makeDate(day: 23, hour: 0)

        #expect(
            ReconcileFormatting.dateRange(periodStart: start, periodEnd: end, calendar: calendar)
                == "16 Nov 2026 – 22 Nov 2026"
        )
    }

    @Test("A session subtitle shows the period and plural message count")
    func sessionSubtitle() throws {
        let start = try makeDate(day: 17, hour: 0)
        let end = try makeDate(day: 22, hour: 18)

        #expect(
            ReconcileFormatting.sessionSubtitle(
                periodStart: start,
                periodEnd: end,
                messageCount: 18,
                calendar: calendar
            ) == "17 Nov 2026 – 22 Nov 2026 · 18 messages"
        )
    }

    @Test("A session subtitle uses a singular message for one message")
    func singularSessionSubtitle() throws {
        let start = try makeDate(day: 17, hour: 0)
        let end = try makeDate(day: 22, hour: 18)

        #expect(
            ReconcileFormatting.sessionSubtitle(
                periodStart: start,
                periodEnd: end,
                messageCount: 1,
                calendar: calendar
            ) == "17 Nov 2026 – 22 Nov 2026 · 1 message"
        )
    }

    @Test("Explanations are explicit about review and never deleting")
    func explanations() {
        #expect(
            ReconcileFormatting.importExplanation == "Creates a needs-review entry; nothing is confirmed automatically."
        )
        #expect(ReconcileFormatting.possibleExplanation.contains("Nothing is linked automatically"))
        #expect(ReconcileFormatting.possibleExplanation.contains("nothing is confirmed automatically"))
        #expect(ReconcileFormatting.ignoreExplanation.contains("Never deletes the entry"))
        #expect(ReconcileFormatting.emptyStateMessage.contains("Messages Shortcut"))
    }

    @Test("The Settings value summarises the latest session state")
    func settingsValue() throws {
        let session = ReconcileSession(
            token: "settings",
            periodStart: try makeDate(day: 17, hour: 0),
            periodEnd: try makeDate(day: 22, hour: 18)
        )
        session.messageCount = 18

        #expect(ReconcileFormatting.settingsValue(for: session) == "18 messages · in progress")

        session.isFinalised = true
        #expect(ReconcileFormatting.settingsValue(for: session) == "18 messages · finalised")
    }
}
