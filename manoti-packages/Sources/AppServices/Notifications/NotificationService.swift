//
//  NotificationService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData
import UserNotifications

/// Builds the local notification plan from the store and hands it to
/// `UNUserNotificationCenter`. Scheduling is always one-shot; every refresh replaces the
/// recurring requests and preserves an imminent budget or large-transaction alert until it
/// has fired.
@Observable
public final class NotificationService: Loggable {
    public static let identifierPrefix = "manoti."

    private static let budgetIdentifierPrefix = "manoti.budget."
    private static let largeIdentifierPrefix = "manoti.large."

    private let context: ModelContext
    private let center: UserNotificationCentering
    private let budgetService: BudgetService
    private let insightsService: InsightsService

    /// The last set handed to the center, so a refresh only broadcasts when the plan changed.
    private var lastPlannedIdentifiers: [String] = []
    private var isRefreshing = false
    private var needsRefresh = false

    public init(context: ModelContext, center: UserNotificationCentering = SystemNotificationCenter()) {
        self.context = context
        self.center = center
        self.budgetService = BudgetService(context: context)
        self.insightsService = InsightsService(context: context)
    }

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        let granted = await center.requestAuthorization()

        if !granted {
            log("Notification authorization was denied", level: .warning)
        }

        return granted
    }

    /// Removes every pending request this app owns, including alerts already scheduled.
    public func cancelAll() {
        center.removePending(identifiers: nil)
        lastPlannedIdentifiers = []
    }

    // MARK: - Refresh

    @discardableResult
    public func refresh(promptForPermission: Bool = true) async -> Bool {
        if isRefreshing {
            // A write arrived while a plan was in flight. Run one more pass afterwards
            // instead of dropping the change.
            needsRefresh = true
            return false
        }

        isRefreshing = true
        defer { isRefreshing = false }

        var success = true

        repeat {
            needsRefresh = false
            let pass = await refreshOnce(promptForPermission: promptForPermission)
            success = success && pass
        } while needsRefresh

        return success
    }

    private func refreshOnce(promptForPermission: Bool) async -> Bool {
        let now = Date()

        do {
            let settings = try settingsRow()

            guard settings.notificationsEnabled else {
                cancelAll()
                return true
            }

            switch await center.authorizationStatus() {
                case .denied:
                    // The system permission is the source of truth. A restore or an iOS
                    // Settings change can leave the app's own flag on after revocation.
                    try disableNotifications(settings)
                    cancelAll()
                    return true

                case .notDetermined:
                    // A background intent cannot present the system permission prompt.
                    guard promptForPermission else {
                        return true
                    }

                    guard await requestAuthorization() else {
                        try disableNotifications(settings)
                        cancelAll()
                        return true
                    }

                default:
                    break
            }

            let calendar = effectiveCalendar(weekStartsOn: settings.weekStartsOn)
            let displayCurrency = CurrencyCatalog.currency(for: settings.displayCurrencyCode)
            let preferences = NotificationPreferences(
                masterEnabled: settings.notificationsEnabled,
                dailyReminderEnabled: settings.dailyReminderEnabled,
                inboxReminderEnabled: settings.inboxReminderEnabled,
                weeklySummaryEnabled: settings.weeklySummaryEnabled,
                budgetAlertsEnabled: settings.budgetAlertsEnabled,
                largeTransactionAlertsEnabled: settings.largeTransactionAlertsEnabled,
                hideAmounts: settings.privacyModeEnabled,
                displayCurrency: displayCurrency,
                largeTransactionThresholdMinor: settings.largeTransactionThresholdMinor
            )

            let hasLoggedToday = try hasLoggedToday(now: now, calendar: calendar)
            let inboxCount = try pendingInboxCount()
            let weekSpend = try weekSpend(now: now, calendar: calendar, displayCurrency: displayCurrency)
            let budgetRows = try currentBudgetRows(
                now: now,
                calendar: calendar,
                displayCurrency: displayCurrency
            )
            let largeEntry = try latestLargeEntry(
                since: settings.lastNotificationScanAt,
                now: now,
                displayCurrency: displayCurrency,
                calendar: calendar
            )

            let planned = NotificationPlanner.plan(
                now: now,
                calendar: calendar,
                hasLoggedToday: hasLoggedToday,
                inboxCount: inboxCount,
                weekSpend: weekSpend,
                budgetRows: budgetRows,
                largeEntry: largeEntry,
                preferences: preferences
            )

            let scheduled = await schedule(planned, preferences: preferences, now: now, calendar: calendar)
            let budgetChanged = try persistBudgetAlerts(planned: planned, scheduled: scheduled)

            // Advance the large-transaction watermark only when its alert was actually
            // scheduled. Otherwise the next pass retries the same entry.
            let largePlanned = planned.first { $0.kind == .largeTransaction }
            let largeScheduled = largePlanned.map { scheduled.contains($0.identifier) } ?? true
            if largeScheduled {
                settings.lastNotificationScanAt = now
            }
            try context.save()

            let identifiers = planned.map(\.identifier)
            if budgetChanged || identifiers != lastPlannedIdentifiers {
                ManotiNotifications.postDataChanged()
            }
            lastPlannedIdentifiers = identifiers
            return true
        } catch {
            log("Notification refresh failed: \(error.localizedDescription)", level: .error)
            return false
        }
    }

    // MARK: - Scheduling

    private func schedule(
        _ planned: [PlannedNotification],
        preferences: NotificationPreferences,
        now: Date,
        calendar: Calendar
    ) async -> Set<String> {
        let plannedIdentifiers = Set(planned.map(\.identifier))
        let pending = (await center.pendingIdentifiers()).filter { $0.hasPrefix(Self.identifierPrefix) }

        // An alert scheduled seconds from now must survive the next refresh, which no longer
        // sees the triggering entry or envelope state.
        let preserved = pending.filter {
            !plannedIdentifiers.contains($0) && shouldPreserve($0, preferences: preferences)
        }

        let stale = pending.filter {
            !plannedIdentifiers.contains($0) && !preserved.contains($0)
        }

        if !stale.isEmpty {
            center.removePending(identifiers: stale)
        }

        var scheduled: Set<String> = []

        for notification in planned {
            do {
                try await center.add(Self.request(for: notification, now: now, calendar: calendar))
                scheduled.insert(notification.identifier)
            } catch NotificationSchedulingError.notAuthorized {
                log("Notifications are not authorized; skipping \(notification.identifier)", level: .warning)
            } catch {
                log("Could not schedule \(notification.identifier): \(error.localizedDescription)", level: .error)
            }
        }

        return scheduled
    }

    private func shouldPreserve(_ identifier: String, preferences: NotificationPreferences) -> Bool {
        if identifier.hasPrefix(Self.budgetIdentifierPrefix) {
            return preferences.budgetAlertsEnabled
        }

        if identifier.hasPrefix(Self.largeIdentifierPrefix) {
            return preferences.largeTransactionAlertsEnabled && preferences.largeTransactionThresholdMinor > 0
        }

        return false
    }

    private static func request(
        for notification: PlannedNotification,
        now: Date,
        calendar: Calendar
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "manoti"
        content.userInfo = ["manoti.kind": notification.kind.rawValue]

        let interval = notification.fireDate.timeIntervalSince(now)
        let trigger: UNNotificationTrigger

        switch notification.kind {
            case .dailyReminder, .inboxReminder:
                // Repeat daily so a reminder survives a few days without opening the app. A
                // refresh cancels it when the condition no longer applies.
                let components = calendar.dateComponents([.hour, .minute], from: notification.fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            case .weeklySummary:
                let components = calendar.dateComponents(
                    [.weekday, .hour, .minute], from: notification.fireDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            default:
                if interval < 60 {
                    trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
                } else {
                    let components = calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: notification.fireDate
                    )
                    trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                }
        }

        return UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
    }

    // MARK: - Budget markers

    /// Records the period that fired for each scheduled budget alert. The marker is what stops
    /// the same envelope crossing the same threshold twice in one period.
    private func persistBudgetAlerts(
        planned: [PlannedNotification],
        scheduled: Set<String>
    ) throws -> Bool {
        var changed = false

        for notification in planned {
            guard notification.kind == .budgetWarning || notification.kind == .budgetOver,
                scheduled.contains(notification.identifier),
                let envelopeID = notification.budgetEnvelopeID,
                let threshold = notification.budgetThresholdPercent,
                let periodStart = notification.budgetPeriodStart
            else {
                continue
            }

            let descriptor = FetchDescriptor<BudgetAlert>(
                predicate: #Predicate<BudgetAlert> {
                    $0.thresholdPercent == threshold && $0.envelope?.id == envelopeID
                }
            )

            let alert: BudgetAlert

            if let existing = try context.fetch(descriptor).first {
                alert = existing
            } else {
                let envelopeDescriptor = FetchDescriptor<Envelope>(
                    predicate: #Predicate<Envelope> { $0.id == envelopeID }
                )

                guard let envelope = try context.fetch(envelopeDescriptor).first else {
                    continue
                }

                alert = BudgetAlert(envelope: envelope, thresholdPercent: threshold)
                context.insert(alert)
                changed = true
            }

            if alert.lastTriggeredPeriodStart != periodStart {
                alert.lastTriggeredPeriodStart = periodStart
                changed = true
            }
        }

        return changed
    }

    // MARK: - Store context

    private func disableNotifications(_ settings: AppSettings) throws {
        settings.notificationsEnabled = false
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    private func settingsRow() throws -> AppSettings {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let created = AppSettings()
        context.insert(created)
        return created
    }

    private func effectiveCalendar(weekStartsOn: Int) -> Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsOn
        return calendar
    }

    private func hasLoggedToday(now: Date, calendar: Calendar) throws -> Bool {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.statusRaw != "ignored" && $0.occurredAt >= start && $0.occurredAt < end
            }
        )

        return try context.fetchCount(descriptor) > 0
    }

    private func pendingInboxCount() throws -> Int {
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.statusRaw == "needsReview"
            }
        )

        return try context.fetchCount(descriptor)
    }

    private func weekSpend(now: Date, calendar: Calendar, displayCurrency: Currency) throws -> Money {
        let interval = BudgetPeriodKind.week.dateInterval(containing: now, calendar: calendar)
        let total = try insightsService.total(
            kind: .expense,
            from: interval.start,
            to: interval.end,
            displayCurrency: displayCurrency
        )
        return total.amount
    }

    private func currentBudgetRows(
        now: Date,
        calendar: Calendar,
        displayCurrency: Currency
    ) throws -> [NotificationBudgetRow] {
        let interval = BudgetPeriodKind.month.dateInterval(containing: now, calendar: calendar)
        let kindRaw = BudgetPeriodKind.month.rawValue
        let start = interval.start
        let descriptor = FetchDescriptor<BudgetPeriod>(
            predicate: #Predicate<BudgetPeriod> {
                $0.kindRaw == kindRaw && $0.startDate == start
            }
        )

        guard let period = try context.fetch(descriptor).first else {
            return []
        }

        let summary = try budgetService.summary(for: period, displayCurrency: displayCurrency, now: now)
        let envelopes = try budgetService.envelopes(for: period)
        var lastAlert: [UUID: Int] = [:]
        var alertable: Set<UUID> = []

        for envelope in envelopes {
            guard !envelope.isArchived, envelope.category?.isArchived == false else {
                continue
            }

            alertable.insert(envelope.id)

            let current = (envelope.alerts ?? [])
                .filter { $0.lastTriggeredPeriodStart == period.startDate }
                .map(\.thresholdPercent)

            if let highest = current.max() {
                lastAlert[envelope.id] = highest
            }
        }

        return summary.envelopes.filter { alertable.contains($0.envelopeID) }.map { row in
            NotificationBudgetRow(
                envelopeID: row.envelopeID,
                categoryName: row.categoryName,
                spentMinor: row.spent.minorUnits,
                limitMinor: row.limit.minorUnits,
                periodStart: period.startDate,
                lastAlertPercent: lastAlert[row.envelopeID] ?? 0
            )
        }
    }

    /// Uses `createdAt` so a backdated or imported entry still qualifies, and returns only the
    /// newest one because a single refresh should not flood the user.
    private func latestLargeEntry(
        since scan: Date?,
        now: Date,
        displayCurrency: Currency,
        calendar: Calendar
    ) throws -> NotificationLargeEntry? {
        // On the first pass there is no watermark. Look back one minute so a write that
        // triggered this refresh can still alert, without replaying old history.
        let since = scan ?? now.addingTimeInterval(-60)

        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.statusRaw != "ignored" && $0.kindRaw == "expense"
                    && $0.createdAt > since && $0.createdAt <= now
            },
            sortBy: [SortDescriptor(\LedgerEntry.createdAt, order: .reverse)]
        )

        var limited = descriptor
        limited.fetchLimit = 1

        guard let entry = try context.fetch(limited).first else {
            return nil
        }

        guard entry.transfer == nil, entry.loan == nil, entry.investmentCashFlow == nil else {
            return nil
        }

        // The threshold is in the display currency, so compare like with like.
        let book = ExchangeRateBook(
            records: try context.fetch(FetchDescriptor<ExchangeRateRecord>()),
            calendar: calendar
        )
        let amount = Money(minorUnits: abs(entry.signedAmountMinor), currency: entry.currency)
        let converted =
            book.convert(amount, to: displayCurrency, on: entry.occurredAt)
            ?? Money(decimal: amount.decimalValue, currency: displayCurrency)
            ?? .zero(in: displayCurrency)

        return NotificationLargeEntry(
            entryID: entry.id,
            amountMinor: converted.minorUnits,
            currencyCode: displayCurrency.code,
            payee: entry.payee,
            occurredAt: entry.occurredAt
        )
    }
}
