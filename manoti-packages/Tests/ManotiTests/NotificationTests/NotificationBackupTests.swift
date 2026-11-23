//
//  NotificationBackupTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Notification settings backup")
struct NotificationBackupTests {
    @Test("Notification flags round-trip, while device-local scan dates are preserved")
    func notificationSettingsRoundTrip() throws {
        let sourceContainer = try ModelContainerFactory.make(inMemory: true)
        let source = ModelContext(sourceContainer)
        let scanDate = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = AppSettings()
        settings.notificationsEnabled = false
        settings.dailyReminderEnabled = false
        settings.inboxReminderEnabled = true
        settings.weeklySummaryEnabled = false
        settings.budgetAlertsEnabled = false
        settings.largeTransactionAlertsEnabled = true
        settings.largeTransactionThresholdMinor = 75_000
        settings.lastNotificationScanAt = scanDate
        source.insert(settings)
        try source.save()

        let data = try ExportService(context: source).backupData(exportedAt: scanDate)

        let targetContainer = try ModelContainerFactory.make(inMemory: true)
        let target = ModelContext(targetContainer)
        _ = try ExportService(context: target).restore(data: data)

        let restored = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(!restored.notificationsEnabled)
        #expect(!restored.dailyReminderEnabled)
        #expect(restored.inboxReminderEnabled)
        #expect(!restored.weeklySummaryEnabled)
        #expect(!restored.budgetAlertsEnabled)
        #expect(restored.largeTransactionAlertsEnabled)
        #expect(restored.largeTransactionThresholdMinor == 75_000)
        // A scan date belongs to the device doing the restore, not to the file.
        #expect(restored.lastNotificationScanAt == nil)
    }
}
