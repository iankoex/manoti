//
//  AppService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum SettingsError: Error, Equatable {
    case unsupportedCurrency
    case invalidWeekStart
    case invalidRate
    case invalidThreshold
}

/// Cross-cutting app state: settings and the display currency.
@Observable
nonisolated public final class AppService: Loggable {
    private let context: ModelContext

    public private(set) var settings: AppSettings?
    public private(set) var startupError: String?

    public init(context: ModelContext) {
        self.context = context
        loadSettings()
    }

    public var displayCurrency: Currency {
        settings?.displayCurrency ?? CurrencyCatalog.defaultCurrency
    }

    public var weekStartsOn: Int {
        settings?.weekStartsOn ?? 2
    }

    /// The portfolio default reinvestment rate, expressed in basis points.
    public var reinvestmentRateBasisPoints: Int {
        settings?.reinvestmentRateBasisPoints ?? AppSettings.defaultReinvestmentRateBasisPoints
    }

    /// The default withholding tax on coupons and interest, expressed in basis points.
    public var withholdingTaxBasisPoints: Int {
        settings?.withholdingTaxBasisPoints ?? AppSettings.defaultWithholdingTaxBasisPoints
    }

    /// Whether Manoti should open with monetary figures masked.
    public var privacyModeEnabled: Bool {
        settings?.privacyModeEnabled ?? false
    }

    /// The master switch for all local notifications.
    public var notificationsEnabled: Bool {
        settings?.notificationsEnabled ?? true
    }

    public var dailyReminderEnabled: Bool {
        settings?.dailyReminderEnabled ?? true
    }

    public var inboxReminderEnabled: Bool {
        settings?.inboxReminderEnabled ?? true
    }

    public var weeklySummaryEnabled: Bool {
        settings?.weeklySummaryEnabled ?? true
    }

    public var budgetAlertsEnabled: Bool {
        settings?.budgetAlertsEnabled ?? true
    }

    public var largeTransactionAlertsEnabled: Bool {
        settings?.largeTransactionAlertsEnabled ?? true
    }

    /// Zero turns large-transaction alerts off even when the flag is on.
    public var largeTransactionThresholdMinor: Int64 {
        settings?.largeTransactionThresholdMinor ?? 0
    }

    public var lastNotificationScanAt: Date? {
        settings?.lastNotificationScanAt
    }

    /// Whether newly ingested messages keep their original body text.
    public var keepRawMessages: Bool {
        settings?.keepRawMessages ?? true
    }

    public func loadSettings() {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        do {
            settings = try context.fetch(descriptor).first
        } catch {
            startupError = error.localizedDescription
            log("Failed to load settings: \(error.localizedDescription)", level: .error)
        }
    }

    public func reload() {
        loadSettings()
    }

    /// Only currencies in the code-owned catalog are selectable, because changing an
    /// exponent would silently rescale every stored amount for that currency.
    public func setDisplayCurrency(_ code: String) throws {
        let normalised = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard let currency = CurrencyCatalog.supported.first(where: { $0.code == normalised }) else {
            throw SettingsError.unsupportedCurrency
        }

        let settings = try settingsRow()
        settings.displayCurrencyCode = currency.code
        try commit(settings)
    }

    /// `weekStartsOn` uses `Calendar`'s weekday numbers: 1 = Sunday, 2 = Monday.
    public func setWeekStartsOn(_ weekday: Int) throws {
        guard (1...7).contains(weekday) else {
            throw SettingsError.invalidWeekStart
        }

        let settings = try settingsRow()
        settings.weekStartsOn = weekday
        try commit(settings)
    }

    /// Accepts 0%–50% so a projection can be deliberately conservative or optimistic.
    public func setReinvestmentRateBasisPoints(_ basisPoints: Int) throws {
        guard (0...5000).contains(basisPoints) else {
            throw SettingsError.invalidRate
        }

        let settings = try settingsRow()
        settings.reinvestmentRateBasisPoints = basisPoints
        try commit(settings)
    }

    /// Withholding tax is editable between 0% and 100%.
    public func setWithholdingTaxBasisPoints(_ basisPoints: Int) throws {
        guard (0...10_000).contains(basisPoints) else {
            throw SettingsError.invalidRate
        }

        let settings = try settingsRow()
        settings.withholdingTaxBasisPoints = basisPoints
        try commit(settings)
    }

    /// Persists the in-app amount privacy preference. The live masking state lives in `PrivacyService`.
    public func setPrivacyModeEnabled(_ enabled: Bool) throws {
        let settings = try settingsRow()
        settings.privacyModeEnabled = enabled
        try commit(settings)
    }

    public func setNotificationsEnabled(_ enabled: Bool) throws {
        let settings = try settingsRow()
        settings.notificationsEnabled = enabled
        try commit(settings)
    }

    public func setDailyReminderEnabled(_ enabled: Bool) throws {
        try updateNotificationPreferences { $0.dailyReminderEnabled = enabled }
    }

    public func setInboxReminderEnabled(_ enabled: Bool) throws {
        try updateNotificationPreferences { $0.inboxReminderEnabled = enabled }
    }

    public func setWeeklySummaryEnabled(_ enabled: Bool) throws {
        try updateNotificationPreferences { $0.weeklySummaryEnabled = enabled }
    }

    public func setBudgetAlertsEnabled(_ enabled: Bool) throws {
        try updateNotificationPreferences { $0.budgetAlertsEnabled = enabled }
    }

    public func setLargeTransactionAlertsEnabled(_ enabled: Bool) throws {
        try updateNotificationPreferences { $0.largeTransactionAlertsEnabled = enabled }
    }

    /// The threshold shares the display currency's minor units. Zero disables the alert.
    public func setLargeTransactionThresholdMinor(_ minorUnits: Int64) throws {
        guard minorUnits >= 0 else {
            throw SettingsError.invalidThreshold
        }

        let settings = try settingsRow()
        settings.largeTransactionThresholdMinor = minorUnits
        try commit(settings)
    }

    /// Recorded by `NotificationService` after each scheduling pass.
    public func setLastNotificationScanAt(_ date: Date?) throws {
        let settings = try settingsRow()
        settings.lastNotificationScanAt = date
        try commit(settings)
    }

    /// Applies to messages ingested from now on.
    ///
    /// Existing entries keep whatever they stored.
    public func setKeepRawMessages(_ keep: Bool) throws {
        let settings = try settingsRow()
        settings.keepRawMessages = keep
        try commit(settings)
    }

    private func updateNotificationPreferences(_ update: (AppSettings) -> Void) throws {
        let settings = try settingsRow()
        update(settings)
        try commit(settings)
    }

    private func settingsRow() throws -> AppSettings {
        if let settings {
            return settings
        }

        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            settings = existing
            return existing
        }

        let created = AppSettings()
        context.insert(created)
        return created
    }

    private func commit(_ settings: AppSettings) throws {
        try context.save()
        self.settings = settings
        ManotiNotifications.postDataChanged()
    }
}
