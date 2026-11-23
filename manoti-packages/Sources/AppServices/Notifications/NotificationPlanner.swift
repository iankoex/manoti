//
//  NotificationPlanner.swift
//  AppServices
//

import AppModels
import Foundation

/// Decides which local notifications should be pending. Pure and independent of the store so
/// the rules are directly testable.
nonisolated public enum NotificationPlanner {
    public static let dailyHour = 20
    public static let inboxHour = 19
    public static let weeklyHour = 18

    /// The last day of the user's week, using `Calendar`'s weekday numbering.
    public static func lastWeekday(in calendar: Calendar) -> Int {
        calendar.firstWeekday == 1 ? 7 : calendar.firstWeekday - 1
    }

    /// Budget and large-transaction alerts fire a few seconds after the refresh that noticed
    /// them, rather than interrupting the user mid-task.
    public static let immediateDelay: TimeInterval = 5

    public static let warningThresholdPercent = 80
    public static let overThresholdPercent = 100

    public static func plan(
        now: Date,
        calendar: Calendar,
        hasLoggedToday: Bool,
        inboxCount: Int,
        weekSpend: Money,
        budgetRows: [NotificationBudgetRow],
        largeEntry: NotificationLargeEntry?,
        preferences: NotificationPreferences
    ) -> [PlannedNotification] {
        guard preferences.masterEnabled else {
            return []
        }

        var planned: [PlannedNotification] = []

        if preferences.dailyReminderEnabled, !hasLoggedToday,
            let fireDate = nextOccurrence(hour: dailyHour, after: now, calendar: calendar)
        {
            planned.append(
                PlannedNotification(
                    identifier: "manoti.daily",
                    title: "Nothing logged today",
                    body: "Add today's spending in Manoti.",
                    fireDate: fireDate,
                    kind: .dailyReminder
                )
            )
        }

        if preferences.inboxReminderEnabled, inboxCount > 0,
            let fireDate = nextOccurrence(hour: inboxHour, after: now, calendar: calendar)
        {
            let noun = inboxCount == 1 ? "message is" : "messages are"
            planned.append(
                PlannedNotification(
                    identifier: "manoti.inbox",
                    title: "Inbox needs review",
                    body: "\(inboxCount) \(noun) waiting in your Inbox.",
                    fireDate: fireDate,
                    kind: .inboxReminder
                )
            )
        }

        if preferences.weeklySummaryEnabled,
            let fireDate = nextOccurrence(
                hour: weeklyHour,
                weekday: lastWeekday(in: calendar),
                after: now,
                calendar: calendar
            )
        {
            // The body is computed now but may fire days later, so it stays generic.
            planned.append(
                PlannedNotification(
                    identifier: "manoti.weekly",
                    title: "Your week in Manoti",
                    body: "Open Manoti to review your week.",
                    fireDate: fireDate,
                    kind: .weeklySummary
                )
            )
        }

        if preferences.budgetAlertsEnabled {
            planned.append(
                contentsOf: budgetNotifications(
                    now: now,
                    rows: budgetRows,
                    preferences: preferences
                )
            )
        }

        if preferences.largeTransactionAlertsEnabled,
            preferences.largeTransactionThresholdMinor > 0,
            let largeEntry,
            largeEntry.amountMinor >= preferences.largeTransactionThresholdMinor
        {
            planned.append(largeTransactionNotification(now: now, entry: largeEntry, preferences: preferences))
        }

        return planned
    }

    // MARK: - Budget

    private static func budgetNotifications(
        now: Date,
        rows: [NotificationBudgetRow],
        preferences: NotificationPreferences
    ) -> [PlannedNotification] {
        let ordered = rows.sorted { $0.envelopeID.uuidString < $1.envelopeID.uuidString }
        let fireDate = now.addingTimeInterval(immediateDelay)
        var notifications: [PlannedNotification] = []

        for row in ordered where row.limitMinor > 0 {

            let percent = Int((row.spentMinor * 100) / row.limitMinor)
            let threshold: Int
            let kind: PlannedNotification.Kind

            if percent >= overThresholdPercent {
                threshold = overThresholdPercent
                kind = .budgetOver
            } else if percent >= warningThresholdPercent {
                threshold = warningThresholdPercent
                kind = .budgetWarning
            } else {
                continue
            }

            guard row.lastAlertPercent < threshold else {
                continue
            }

            let spent = Money(minorUnits: row.spentMinor, currency: preferences.displayCurrency)
            let limit = Money(minorUnits: row.limitMinor, currency: preferences.displayCurrency)
            let title = kind == .budgetOver ? "Budget exceeded" : "Budget almost used"
            let body: String

            if preferences.hideAmounts {
                body =
                    kind == .budgetOver
                    ? "\(row.categoryName) is over budget."
                    : "You've used \(percent)% of \(row.categoryName)."
            } else {
                body =
                    kind == .budgetOver
                    ? "\(row.categoryName) is over budget (\(spent.formatted()) of \(limit.formatted()))."
                    : "You've used \(percent)% of \(row.categoryName) (\(spent.formatted()) of \(limit.formatted()))."
            }

            notifications.append(
                PlannedNotification(
                    identifier: "manoti.budget.\(row.envelopeID.uuidString).\(threshold)",
                    title: title,
                    body: body,
                    fireDate: fireDate,
                    kind: kind,
                    budgetEnvelopeID: row.envelopeID,
                    budgetThresholdPercent: threshold,
                    budgetPeriodStart: row.periodStart
                )
            )
        }

        return notifications
    }

    // MARK: - Large transaction

    private static func largeTransactionNotification(
        now: Date,
        entry: NotificationLargeEntry,
        preferences: NotificationPreferences
    ) -> PlannedNotification {
        let money = Money(
            minorUnits: entry.amountMinor,
            currency: CurrencyCatalog.currency(for: entry.currencyCode)
        )
        let body: String

        if preferences.hideAmounts {
            body =
                entry.payee.isEmpty
                ? "A large transaction was recorded. Open Manoti to review it."
                : "\(entry.payee) — a large transaction was recorded. Open Manoti to review it."
        } else {
            body =
                entry.payee.isEmpty
                ? "\(money.formatted()) was recorded. Open Manoti to review it."
                : "\(entry.payee) — \(money.formatted()). Open Manoti to review it."
        }

        return PlannedNotification(
            identifier: "manoti.large.\(entry.entryID.uuidString)",
            title: "Large transaction",
            body: body,
            fireDate: now.addingTimeInterval(immediateDelay),
            kind: .largeTransaction
        )
    }

    // MARK: - Dates

    private static func nextOccurrence(
        hour: Int,
        weekday: Int? = nil,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.weekday = weekday

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}
