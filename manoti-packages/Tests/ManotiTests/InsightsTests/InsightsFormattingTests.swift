//
//  InsightsFormattingTests.swift
//  ManotiTests
//

import AppModels
import AppServices
import Foundation
import InsightsFeature
import Testing

@MainActor
@Suite("Insights formatting")
struct InsightsFormattingTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        )
    }

    @Test("Same-month windows use compact day ranges")
    func sameMonthRanges() throws {
        let current = DateInterval(
            start: try date(2026, 11, 1),
            end: try date(2026, 11, 23)
        )
        let previous = DateInterval(
            start: try date(2026, 10, 1),
            end: try date(2026, 10, 23)
        )

        #expect(
            InsightsFormatting.windowDescription(
                current: current,
                previous: previous,
                calendar: calendar,
                locale: locale
            ) == "1–22 Nov vs 1–22 Oct"
        )
        #expect(
            InsightsFormatting.windowSummary(
                current: current,
                previous: previous,
                kind: .month,
                elapsedDays: 22,
                calendar: calendar,
                locale: locale
            ) == "1–22 Nov vs 1–22 Oct · day 22 of 30"
        )
    }

    @Test("Weeks spanning two months name both months")
    func crossMonthRanges() throws {
        let current = DateInterval(
            start: try date(2026, 11, 30),
            end: try date(2026, 12, 7)
        )
        let previous = DateInterval(
            start: try date(2026, 11, 23),
            end: try date(2026, 11, 30)
        )

        #expect(
            InsightsFormatting.windowDescription(
                current: current,
                previous: previous,
                calendar: calendar,
                locale: locale
            ) == "30 Nov–6 Dec vs 23–29 Nov"
        )
    }

    @Test("Weeks spanning two years name both years")
    func crossYearRanges() throws {
        let current = DateInterval(
            start: try date(2025, 12, 29),
            end: try date(2026, 1, 5)
        )
        let previous = DateInterval(
            start: try date(2025, 12, 22),
            end: try date(2025, 12, 29)
        )

        #expect(
            InsightsFormatting.windowDescription(
                current: current,
                previous: previous,
                calendar: calendar,
                locale: locale
            ) == "29 Dec 2025–4 Jan 2026 vs 22–28 Dec 2025"
        )
    }

    @Test("Day counters use the full period length")
    func dayCounters() throws {
        #expect(InsightsFormatting.dayCounter(elapsedDays: 22, totalDays: 30) == "Day 22 of 30")
        #expect(
            InsightsFormatting.totalDays(
                kind: .month,
                containing: try date(2026, 11, 22),
                calendar: calendar
            ) == 30
        )
        #expect(
            InsightsFormatting.totalDays(
                kind: .month,
                containing: try date(2026, 2, 10),
                calendar: calendar
            ) == 28
        )
    }

    @Test("Signed percentages show direction and one decimal")
    func signedPercentages() {
        #expect(InsightsFormatting.signedPercent(12.44) == "+12.4%")
        #expect(InsightsFormatting.signedPercent(-3.0) == "−3.0%")
        #expect(InsightsFormatting.signedPercent(0) == "0.0%")
        #expect(InsightsFormatting.signedPercent(-0.04) == "0.0%")
    }

    @Test("A missing percentage stays missing")
    func missingPercentage() {
        #expect(InsightsFormatting.signedPercent(nil) == nil)
        #expect(InsightsFormatting.signedPercent(.nan) == nil)
        #expect(InsightsFormatting.signedPercent(.infinity) == nil)
    }

    @Test("Shares round to whole percentages and need a total")
    func sharePercentages() {
        #expect(InsightsFormatting.sharePercent(partMinor: 1, totalMinor: 3) == "33%")
        #expect(InsightsFormatting.sharePercent(partMinor: 2, totalMinor: 3) == "67%")
        #expect(InsightsFormatting.sharePercent(partMinor: 1, totalMinor: 6) == "17%")
        #expect(InsightsFormatting.sharePercent(partMinor: 0, totalMinor: 0) == nil)
    }

    @Test("Small spend summaries pluralise and mask")
    func smallSpendSummaries() {
        let currency = Currency(code: "KES", exponent: 2)
        let threshold = Money(minorUnits: 50_000, currency: currency)
        let total = Money(minorUnits: 32_000, currency: currency)

        #expect(
            InsightsFormatting.smallSpendSummary(count: 1, threshold: threshold, total: total)
                .hasPrefix("1 purchase ≤ ")
        )
        #expect(
            InsightsFormatting.smallSpendSummary(count: 7, threshold: threshold, total: total)
                .hasPrefix("7 purchases ≤ ")
        )
        #expect(
            InsightsFormatting.smallSpendSummary(
                count: 7,
                threshold: threshold,
                total: total,
                hidden: true
            ) == "7 purchases ≤ ••••, •••• total"
        )
    }
}
