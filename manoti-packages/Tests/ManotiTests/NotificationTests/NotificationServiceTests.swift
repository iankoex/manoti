//
//  NotificationServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing
import UserNotifications

@testable import AppModels
@testable import AppServices

@MainActor
private final class FakeNotificationCenter: UserNotificationCentering {
    var authorized = true
    var authorization: UNAuthorizationStatus = .authorized
    var failingIdentifiers: Set<String> = []
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removals: [[String]?] = []
    private(set) var pending: [String] = []

    func requestAuthorization() async -> Bool {
        authorized
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorization
    }

    func add(_ request: UNNotificationRequest) async throws {
        guard authorized, !failingIdentifiers.contains(request.identifier) else {
            throw NotificationSchedulingError.notAuthorized
        }

        added.append(request)
        pending.removeAll { $0 == request.identifier }
        pending.append(request.identifier)
    }

    func pendingIdentifiers() async -> [String] {
        pending
    }

    func removePending(identifiers: [String]?) {
        removals.append(identifiers)

        if let identifiers {
            pending.removeAll { identifiers.contains($0) }
        } else {
            pending.removeAll()
        }
    }
}

@MainActor
@Suite("NotificationService")
struct NotificationServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    @discardableResult
    private func insertSettings(
        in context: ModelContext,
        configure: (AppSettings) -> Void = { _ in }
    ) throws -> AppSettings {
        let settings = AppSettings()
        settings.notificationsEnabled = true
        configure(settings)
        context.insert(settings)
        try context.save()
        return settings
    }

    private func makeService(
        context: ModelContext,
        fake: FakeNotificationCenter
    ) -> NotificationService {
        NotificationService(context: context, center: fake)
    }

    @Test("A refresh schedules the recurring reminders")
    func schedulesRecurringNotifications() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let fake = FakeNotificationCenter()
        let service = makeService(context: context, fake: fake)

        await service.refresh()

        #expect(fake.pending.contains("manoti.daily"))
        #expect(fake.pending.contains("manoti.weekly"))
        #expect(fake.pending.count == Set(fake.pending).count)
        #expect(settings.lastNotificationScanAt != nil)

        let daily = fake.added.first { $0.identifier == "manoti.daily" }
        let weekly = fake.added.first { $0.identifier == "manoti.weekly" }
        #expect(daily?.trigger?.repeats == true)
        #expect(weekly?.trigger?.repeats == true)
    }

    @Test("A first refresh still alerts a just-created large entry")
    func firstLargeAlert() async throws {
        let context = try makeContext()
        _ = try insertSettings(in: context) { settings in
            settings.largeTransactionAlertsEnabled = true
            settings.largeTransactionThresholdMinor = 100_000
            settings.lastNotificationScanAt = nil
        }

        let accounts = AccountService(context: context)
        let ledger = LedgerService(context: context)
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try ledger.record(kind: .expense, amountMinor: 200_000, account: account)

        let fake = FakeNotificationCenter()
        let service = makeService(context: context, fake: fake)
        await service.refresh()

        #expect(fake.pending.contains("manoti.large.\(entry.id.uuidString)"))
    }

    @Test("A background refresh never prompts for permission")
    func backgroundRefreshDoesNotPrompt() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let fake = FakeNotificationCenter()
        fake.authorization = .notDetermined
        fake.authorized = false
        let service = makeService(context: context, fake: fake)

        await service.refresh(promptForPermission: false)

        #expect(fake.pending.isEmpty)
        #expect(settings.notificationsEnabled)
    }

    @Test("A failed large alert does not advance the scan watermark")
    func failedLargeAlertRetries() async throws {
        let context = try makeContext()
        let past = Date().addingTimeInterval(-3_600)
        let settings = try insertSettings(in: context) { settings in
            settings.largeTransactionAlertsEnabled = true
            settings.largeTransactionThresholdMinor = 100_000
            settings.lastNotificationScanAt = past
        }

        let accounts = AccountService(context: context)
        let ledger = LedgerService(context: context)
        let account = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let entry = try ledger.record(kind: .expense, amountMinor: 200_000, account: account)

        let fake = FakeNotificationCenter()
        fake.failingIdentifiers = ["manoti.large.\(entry.id.uuidString)"]
        let service = makeService(context: context, fake: fake)

        await service.refresh()
        #expect(settings.lastNotificationScanAt == past)

        fake.failingIdentifiers = []
        await service.refresh()
        #expect((settings.lastNotificationScanAt ?? past) > past)
    }

    @Test("Nothing is scheduled while the master switch is off")
    func masterOffCancels() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context) { settings in
            settings.notificationsEnabled = false
        }
        let fake = FakeNotificationCenter()
        fake.removePending(identifiers: nil)
        let service = makeService(context: context, fake: fake)

        await service.refresh()

        #expect(fake.added.isEmpty)
        #expect(fake.pending.isEmpty)
        #expect(settings.lastNotificationScanAt == nil)
    }

    @Test("A second refresh replaces requests instead of duplicating them")
    func refreshReplacesPending() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let fake = FakeNotificationCenter()
        let service = makeService(context: context, fake: fake)

        await service.refresh()
        await service.refresh()

        #expect(fake.pending.count == Set(fake.pending).count)

        settings.dailyReminderEnabled = false
        try context.save()

        await service.refresh()

        #expect(!fake.pending.contains("manoti.daily"))
        #expect(fake.pending.contains("manoti.weekly"))
    }

    @Test("A large transaction is scheduled once and survives the next refresh")
    func largeTransactionScheduledOnce() async throws {
        let context = try makeContext()
        let scan = Date(timeIntervalSinceNow: -60)
        let settings = try insertSettings(in: context) { settings in
            settings.lastNotificationScanAt = scan
            settings.largeTransactionThresholdMinor = 5_000
        }
        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 9_000,
            currencyCode: "KES",
            payee: "Furniture",
            source: .manual
        )
        entry.status = .confirmed
        context.insert(entry)
        try context.save()

        let fake = FakeNotificationCenter()
        let service = makeService(context: context, fake: fake)

        await service.refresh()

        let identifier = "manoti.large.\(entry.id.uuidString)"
        #expect(fake.pending.contains(identifier))
        #expect(settings.lastNotificationScanAt ?? scan > scan)

        await service.refresh()

        #expect(fake.pending.contains(identifier))
        #expect(fake.added.filter { $0.identifier == identifier }.count == 1)
    }

    @Test("Budget alert markers are written once per envelope and period")
    func budgetAlertMarkersAreIdempotent() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let budgetService = BudgetService(context: context)
        let now = Date()
        let period = try budgetService.currentPeriod(kind: .month, containing: now, calendar: .current)
        let category = SpendingCategory(
            name: "Food",
            symbolName: "fork.knife",
            colorHex: "#FF9500",
            isFixed: false,
            sortIndex: 0
        )
        context.insert(category)
        let envelope = try budgetService.setEnvelope(
            category: category,
            limitMinor: 10_000,
            rolloverEnabled: false,
            in: period
        )
        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 8_500,
            currencyCode: "KES",
            occurredAt: now,
            payee: "Lunch",
            source: .manual
        )
        entry.category = category
        entry.status = .confirmed
        context.insert(entry)
        try context.save()

        let fake = FakeNotificationCenter()
        let service = makeService(context: context, fake: fake)

        await service.refresh()

        let identifier = "manoti.budget.\(envelope.id.uuidString).80"
        let alerts = try context.fetch(FetchDescriptor<BudgetAlert>())
        #expect(alerts.count == 1)
        #expect(alerts.first?.thresholdPercent == 80)
        #expect(alerts.first?.lastTriggeredPeriodStart == period.startDate)
        #expect(fake.pending.contains(identifier))

        await service.refresh()

        let after = try context.fetch(FetchDescriptor<BudgetAlert>())
        #expect(after.count == 1)
        #expect(after.first?.lastTriggeredPeriodStart == period.startDate)
        #expect(fake.pending.contains(identifier))
        #expect(fake.added.filter { $0.identifier == identifier }.count == 1)
        #expect(settings.lastNotificationScanAt != nil)
    }

    @Test("A denied authorization is logged without throwing or crashing")
    func deniedAuthorization() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let fake = FakeNotificationCenter()
        fake.authorized = false
        fake.authorization = .denied
        let service = makeService(context: context, fake: fake)

        let granted = await service.requestAuthorization()
        await service.refresh()

        #expect(!granted)
        #expect(fake.added.isEmpty)
        #expect(fake.pending.isEmpty)
        #expect(!settings.notificationsEnabled)
    }

    @Test("An undetermined authorization is requested and a refusal turns the switch off")
    func undeterminedAuthorization() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let fake = FakeNotificationCenter()
        fake.authorized = false
        fake.authorization = .notDetermined
        let service = makeService(context: context, fake: fake)

        await service.refresh()

        #expect(fake.added.isEmpty)
        #expect(!settings.notificationsEnabled)
    }

    @Test("An undetermined authorization that is granted schedules normally")
    func undeterminedThenGranted() async throws {
        let context = try makeContext()
        let settings = try insertSettings(in: context)
        let fake = FakeNotificationCenter()
        fake.authorization = .notDetermined
        let service = makeService(context: context, fake: fake)

        await service.refresh()

        #expect(settings.notificationsEnabled)
        #expect(fake.pending.contains("manoti.daily"))
    }
}
