//
//  AppMaintenance.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

/// The work that must follow a write, whether it came from the UI or a Shortcut.
///
/// Keeping this out of the view tree is what makes background Shortcut writes schedule
/// notifications and refresh the widget when Manoti is not open.
@Observable
@MainActor
public final class AppMaintenance: Loggable {
    public struct Report: Equatable, Sendable {
        public let ranAt: Date
        public let outboxDrained: Int
        public let investmentsSettled: Int
        public let notificationsRefreshed: Bool
        public let widgetRefreshed: Bool
    }

    private let context: ModelContext
    public private(set) var lastRunAt: Date?
    public private(set) var lastReport: Report?

    public init(context: ModelContext) {
        self.context = context
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            lastRunAt = settings.lastMaintenanceAt
        }
    }

    /// Runs the complete post-write pipeline. Safe to call from every intent and every save.
    @discardableResult
    public func runAfterWrite(promptForNotifications: Bool = false, now: Date = Date()) async -> Report {
        let outbox = IngestOutbox()
        let ingest = IngestService(context: context)
        let drained = (try? outbox.drain(into: ingest)) ?? 0

        let investmentService = InvestmentService(context: context)
        let settled = (try? investmentService.settlePendingInvestments(now: now)) ?? 0

        let notificationsRefreshed = await NotificationService(context: context)
            .refresh(promptForPermission: promptForNotifications)

        let widgetRefreshed = WidgetSnapshotService(context: context).refresh(at: now) != nil

        recordRun(at: now)
        await AppBackgroundScheduler.schedule()

        let report = Report(
            ranAt: now,
            outboxDrained: drained,
            investmentsSettled: settled,
            notificationsRefreshed: notificationsRefreshed,
            widgetRefreshed: widgetRefreshed
        )
        lastRunAt = now
        lastReport = report
        return report
    }

    /// Drains parked messages without touching notifications. Used at launch before the
    /// first frame, where awaiting the full pipeline is not possible.
    public func drainAtLaunch() -> Int {
        let ingest = IngestService(context: context)
        return (try? IngestOutbox().drain(into: ingest)) ?? 0
    }

    private func recordRun(at date: Date) {
        guard let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first else {
            return
        }

        // Avoid a CloudKit write on every small save; the diagnostics only need minute detail.
        if let last = settings.lastMaintenanceAt, date.timeIntervalSince(last) < 60 {
            return
        }

        settings.lastMaintenanceAt = date
        try? context.save()
    }
}
