//
//  ReconcileFormatting.swift
//  ReconcileFeature
//

import AppModels
import Foundation

/// The two periods a reconciliation session can cover.
nonisolated public enum ReconcilePeriodPreset: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Midnight today until the moment the session starts.
    case today
    /// Midnight seven days ago until the moment the session starts.
    case lastSevenDays

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .today: "Today"
            case .lastSevenDays: "Last 7 days"
        }
    }

    /// Builds the half-open period the Shortcut should collect over.
    public func dateInterval(calendar: Calendar, now: Date) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)

        let start: Date
        switch self {
            case .today:
                start = startOfToday
            case .lastSevenDays:
                start = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        }

        return DateInterval(start: start, end: max(start, now))
    }
}

/// The four review buckets on the reconcile screen.
nonisolated public enum ReconcileBucket: String, CaseIterable, Hashable, Identifiable, Sendable {
    case matched
    case missing
    case notInMessages
    case possible

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .matched: "Matched"
            case .missing: "Missing from app"
            case .notInMessages: "Not in messages"
            case .possible: "Possible"
        }
    }

    /// The not-in-messages bucket counts ledger entries rather than collected messages.
    public var countsEntries: Bool {
        self == .notInMessages
    }
}

/// Small, testable strings shared by the reconcile screen and its Settings entry.
public enum ReconcileFormatting {
    public static let importExplanation = "Creates a needs-review entry; nothing is confirmed automatically."

    public static let possibleExplanation =
        "Possible duplicate. Nothing is linked automatically. Importing creates a needs-review entry; nothing is confirmed automatically."

    public static let ignoreExplanation =
        "Ignore only hides this entry from this session. Never deletes the entry."

    public static let notInMessagesExplanation =
        "Posted entries in this period that no message matched. Ignoring one keeps it in the ledger."

    public static let unfinalisedExplanation =
        "Finalise to match the collected messages against posted ledger entries and fill the buckets."

    public static let emptyStateMessage =
        "The Messages Shortcut collects bank and mobile-money messages for a period, then finalises the run. Start a session to review what it found."

    /// "1 message" or "18 messages".
    public static func messageCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "message" : "messages")"
    }

    /// "1 entry" or "2 entries".
    public static func entryCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "entry" : "entries")"
    }

    /// A segmented-control label that carries its bucket count.
    public static func bucketTitle(for bucket: ReconcileBucket, count: Int) -> String {
        if bucket.countsEntries {
            return "\(bucket.displayName) (\(entryCountText(count)))"
        }

        return "\(bucket.displayName) (\(count))"
    }

    /// "17 Nov 2026 – 22 Nov 2026", or a single date when the session covers one day.
    public static func dateRange(periodStart: Date, periodEnd: Date, calendar: Calendar = .current) -> String {
        let formatter = dateFormatter(calendar: calendar)
        let start = calendar.startOfDay(for: periodStart)
        let end = lastIncludedDay(periodStart: periodStart, periodEnd: periodEnd, calendar: calendar)

        if calendar.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }

        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    /// "17 Nov 2026 – 22 Nov 2026 · 18 messages".
    public static func sessionSubtitle(
        periodStart: Date,
        periodEnd: Date,
        messageCount: Int,
        calendar: Calendar = .current
    ) -> String {
        let range = dateRange(periodStart: periodStart, periodEnd: periodEnd, calendar: calendar)
        return "\(range) · \(messageCountText(messageCount))"
    }

    /// The secondary value on the Settings row for a session.
    public static func settingsValue(for session: ReconcileSession) -> String {
        let state = session.isFinalised ? "finalised" : "in progress"
        return "\(messageCountText(session.messageCount)) · \(state)"
    }

    private static func lastIncludedDay(periodStart: Date, periodEnd: Date, calendar: Calendar) -> Date {
        let endDay = calendar.startOfDay(for: periodEnd)

        // Periods are half-open: an end at midnight belongs to the previous day.
        if endDay == periodEnd, endDay > periodStart,
            let previous = calendar.date(byAdding: .day, value: -1, to: endDay)
        {
            return previous
        }

        return endDay
    }

    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }
}
