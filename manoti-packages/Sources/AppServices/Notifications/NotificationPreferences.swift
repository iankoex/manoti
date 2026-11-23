//
//  NotificationPreferences.swift
//  AppServices
//

import AppModels
import Foundation

/// Everything the planner needs to decide whether a notification should exist.
///
/// These are scalars copied from `AppSettings` at refresh time, so planning stays pure and
/// does not touch the store.
nonisolated public struct NotificationPreferences: Sendable, Equatable {
    public var masterEnabled: Bool
    public var dailyReminderEnabled: Bool
    public var inboxReminderEnabled: Bool
    public var weeklySummaryEnabled: Bool
    public var budgetAlertsEnabled: Bool
    public var largeTransactionAlertsEnabled: Bool
    public var hideAmounts: Bool
    public var displayCurrency: Currency
    public var largeTransactionThresholdMinor: Int64

    public init(
        masterEnabled: Bool = true,
        dailyReminderEnabled: Bool = true,
        inboxReminderEnabled: Bool = true,
        weeklySummaryEnabled: Bool = true,
        budgetAlertsEnabled: Bool = true,
        largeTransactionAlertsEnabled: Bool = true,
        hideAmounts: Bool = false,
        displayCurrency: Currency = CurrencyCatalog.defaultCurrency,
        largeTransactionThresholdMinor: Int64 = 0
    ) {
        self.masterEnabled = masterEnabled
        self.dailyReminderEnabled = dailyReminderEnabled
        self.inboxReminderEnabled = inboxReminderEnabled
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.budgetAlertsEnabled = budgetAlertsEnabled
        self.largeTransactionAlertsEnabled = largeTransactionAlertsEnabled
        self.hideAmounts = hideAmounts
        self.displayCurrency = displayCurrency
        self.largeTransactionThresholdMinor = largeTransactionThresholdMinor
    }
}
