//
//  AppSettings.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class AppSettings {
    /// 12% gross reinvestment by default; projections net this by withholding tax.
    public static let defaultReinvestmentRateBasisPoints = 1200
    /// 10% withholding tax by default.
    public static let defaultWithholdingTaxBasisPoints = 1000

    public var id: UUID = UUID()
    public var displayCurrencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var weekStartsOn: Int = 2
    public var lockEnabled: Bool = false
    public var lockAfterSeconds: Int = 60
    public var notificationsEnabled: Bool = false
    public var dailyReminderEnabled: Bool = true
    public var inboxReminderEnabled: Bool = true
    public var weeklySummaryEnabled: Bool = true
    public var budgetAlertsEnabled: Bool = true
    public var largeTransactionAlertsEnabled: Bool = true
    public var privacyModeEnabled: Bool = false
    public var largeTransactionThresholdMinor: Int64 = 0
    public var lastNotificationScanAt: Date?
    public var keepRawMessages: Bool = true
    public var categoryKindsMigrated: Bool = false
    public var categoryKindsRepaired: Bool = false
    public var lastBackupAt: Date?
    /// Last time the post-write pipeline completed (outbox, settlement, notifications, widget).
    public var lastMaintenanceAt: Date?
    public var reinvestmentRateBasisPoints: Int = AppSettings.defaultReinvestmentRateBasisPoints
    public var withholdingTaxBasisPoints: Int = AppSettings.defaultWithholdingTaxBasisPoints

    public init() {
        self.id = UUID()
    }

    public var displayCurrency: Currency {
        CurrencyCatalog.currency(for: displayCurrencyCode)
    }
}
