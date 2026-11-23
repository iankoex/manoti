//
//  InsightsFormatting.swift
//  InsightsFeature
//

import AppModels
import AppServices
import Foundation
import Modifiers

/// Pure, testable formatting helpers for the Insights screen.
public enum InsightsFormatting {
    /// A human range for the two equal-elapsed windows, for example
    /// `"1–22 Nov vs 1–22 Oct"`. Weeks that cross a month or year keep enough
    /// context to stay unambiguous.
    public static func windowDescription(
        current: DateInterval,
        previous: DateInterval,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        let showsYear =
            spansYears(current, calendar: calendar) || spansYears(previous, calendar: calendar)
            || calendar.component(.year, from: current.start) != calendar.component(.year, from: previous.start)
        let currentText = rangeDescription(
            current,
            includesYear: showsYear,
            calendar: calendar,
            locale: locale
        )
        let previousText = rangeDescription(
            previous,
            includesYear: showsYear,
            calendar: calendar,
            locale: locale
        )
        return "\(currentText) vs \(previousText)"
    }

    /// The complete hero line, for example `"1–22 Nov vs 1–22 Oct · day 22 of 30"`.
    public static func windowSummary(
        current: DateInterval,
        previous: DateInterval,
        kind: InsightPeriodKind,
        elapsedDays: Int,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        let description = windowDescription(
            current: current,
            previous: previous,
            calendar: calendar,
            locale: locale
        )
        let total = totalDays(kind: kind, containing: current.start, calendar: calendar)
        return "\(description) · \(dayCounter(elapsedDays: elapsedDays, totalDays: total).lowercased())"
    }

    /// `"Day 22 of 30"`.
    public static func dayCounter(elapsedDays: Int, totalDays: Int) -> String {
        "Day \(max(1, elapsedDays)) of \(max(1, totalDays))"
    }

    /// Length of the whole calendar period that contains `date`, not just its elapsed part.
    public static func totalDays(
        kind: InsightPeriodKind,
        containing date: Date,
        calendar: Calendar
    ) -> Int {
        let component: Calendar.Component =
            switch kind {
                case .month: .month
                case .week: .weekOfYear
            }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return 1
        }

        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    /// A signed one-decimal percentage, or `nil` when there is nothing to compare.
    ///
    /// Uses a real minus sign (U+2212) so the value aligns with other tabular figures in
    /// the app. Zero is unsigned.
    public static func signedPercent(_ value: Double?) -> String? {
        guard let value, value.isFinite else {
            return nil
        }

        let rounded = (value * 10).rounded() / 10
        guard rounded != 0 else {
            return "0.0%"
        }

        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", abs(rounded)))%"
    }

    /// A whole-number share of a total, or `nil` when there is no total to divide by.
    public static func sharePercent(partMinor: Int64, totalMinor: Int64) -> String? {
        guard totalMinor > 0 else {
            return nil
        }

        let percentage = Int((Double(partMinor) / Double(totalMinor) * 100).rounded())
        return "\(min(100, max(0, percentage)))%"
    }

    /// `"7 purchases ≤ KES 500.00, KES 1,240.00 total"`.
    ///
    /// `hidden` mirrors privacy mode and is useful for accessibility labels without
    /// leaking the figures on screen.
    public static func smallSpendSummary(
        count: Int,
        threshold: Money,
        total: Money,
        hidden: Bool = false
    ) -> String {
        let noun = count == 1 ? "purchase" : "purchases"
        return
            "\(count) \(noun) ≤ \(AmountMask.money(threshold, hidden: hidden)), \(AmountMask.money(total, hidden: hidden)) total"
    }

    // MARK: - Ranges

    private static func rangeDescription(
        _ interval: DateInterval,
        includesYear: Bool,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let start = calendar.startOfDay(for: interval.start)
        let last = lastIncludedDay(in: interval, calendar: calendar)
        let startComponents = calendar.dateComponents([.year, .month, .day], from: start)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: last)
        let startDay = startComponents.day ?? 1
        let endDay = endComponents.day ?? startDay
        let startMonth = monthAbbreviation(start, locale: locale)
        let endMonth = monthAbbreviation(last, locale: locale)

        if startComponents.year == endComponents.year && startComponents.month == endComponents.month {
            if startDay == endDay {
                return "\(startDay) \(startMonth)\(yearSuffix(startComponents, includesYear: includesYear))"
            }

            return
                "\(startDay)–\(endDay) \(startMonth)\(yearSuffix(startComponents, includesYear: includesYear))"
        }

        let startText = "\(startDay) \(startMonth)"
        let endText = "\(endDay) \(endMonth)"

        if startComponents.year == endComponents.year {
            let suffix = yearSuffix(startComponents, includesYear: includesYear)
            return "\(startText)\(suffix)–\(endText)\(suffix)"
        }

        let startYear = startComponents.year ?? 0
        let endYear = endComponents.year ?? 0
        return "\(startText) \(startYear)–\(endText) \(endYear)"
    }

    /// The interval end is exclusive. The current window may end mid-day, while previous
    /// windows end at midnight, so both forms need to resolve to the last day the user sees.
    private static func lastIncludedDay(in interval: DateInterval, calendar: Calendar) -> Date {
        let endDay = calendar.startOfDay(for: interval.end)

        if interval.end == endDay {
            return calendar.date(byAdding: .day, value: -1, to: endDay) ?? endDay
        }

        return endDay
    }

    private static func spansYears(_ interval: DateInterval, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: interval.start)
        let last = lastIncludedDay(in: interval, calendar: calendar)
        return calendar.component(.year, from: start) != calendar.component(.year, from: last)
    }

    private static func monthAbbreviation(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(locale))
    }

    private static func yearSuffix(_ components: DateComponents, includesYear: Bool) -> String {
        guard includesYear, let year = components.year else {
            return ""
        }

        return " \(year)"
    }
}
