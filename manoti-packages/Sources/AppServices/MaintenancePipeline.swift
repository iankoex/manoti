//
//  MaintenancePipeline.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import SwiftData

/// What one maintenance pass actually did.
nonisolated public struct MaintenanceReport: Equatable, Sendable {
    public let ranAt: Date
    public let outboxDrained: Int
    public let investmentsSettled: Int
    public let notificationsRefreshed: Bool
    public let widgetRefreshed: Bool

    public init(
        ranAt: Date,
        outboxDrained: Int,
        investmentsSettled: Int,
        notificationsRefreshed: Bool,
        widgetRefreshed: Bool
    ) {
        self.ranAt = ranAt
        self.outboxDrained = outboxDrained
        self.investmentsSettled = investmentsSettled
        self.notificationsRefreshed = notificationsRefreshed
        self.widgetRefreshed = widgetRefreshed
    }
}

/// The work that must follow a write, expressed against a single `ModelContext`.
///
/// The pipeline is deliberately `nonisolated`: it belongs to whichever isolation domain owns the
/// context it was built with. The app runs it on the main context from the UI and from App
/// Intents (`AppMaintenance`), while a `BGTask` runs it on a private context through
/// `MaintenanceWorker`. Keeping the pipeline isolation-agnostic is what lets background work run
/// without the main actor being available.
nonisolated public struct MaintenancePipeline {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Runs

    /// Runs the complete post-write pipeline. Safe to call from every intent and every save.
    ///
    /// `isStopped` lets a background task abandon the pass between stages when the system expires
    /// it, without forcing an actor hop to cancel a task. It defaults to Swift task cancellation,
    /// which is what the foreground and App Intent paths rely on.
    @discardableResult
    public func runAfterWrite(
        promptForNotifications: Bool = false,
        now: Date = Date(),
        isStopped: @Sendable () -> Bool = { Task.isCancelled }
    ) async -> MaintenanceReport {
        let drained = stop(isStopped) ? 0 : drainPendingMessages()
        let settled = settlePendingInvestments(now: now, isStopped: isStopped)
        let notificationsRefreshed = await refreshNotifications(
            promptForNotifications: promptForNotifications,
            isStopped: isStopped
        )
        let widgetRefreshed = refreshWidget(at: now, isStopped: isStopped)

        recordRun(at: now, isStopped: isStopped)

        await AppBackgroundScheduler.schedule()

        return MaintenanceReport(
            ranAt: now,
            outboxDrained: drained,
            investmentsSettled: settled,
            notificationsRefreshed: notificationsRefreshed,
            widgetRefreshed: widgetRefreshed
        )
    }

    /// Replays parked messages without touching notifications. Used at launch before the first
    /// frame, where awaiting the full pipeline is not possible.
    @discardableResult
    public func drainPendingMessages() -> Int {
        guard !Task.isCancelled else {
            return 0
        }

        let ingest = IngestService(context: context)
        return (try? IngestOutbox().drain(into: ingest)) ?? 0
    }

    // MARK: - Stages

    private func stop(_ isStopped: @Sendable () -> Bool) -> Bool {
        isStopped() || Task.isCancelled
    }

    private func settlePendingInvestments(now: Date, isStopped: @Sendable () -> Bool) -> Int {
        guard !stop(isStopped) else {
            return 0
        }

        let service = InvestmentService(context: context)
        return (try? service.settlePendingInvestments(now: now)) ?? 0
    }

    private func refreshNotifications(
        promptForNotifications: Bool,
        isStopped: @Sendable () -> Bool
    ) async -> Bool {
        guard !stop(isStopped) else {
            return false
        }

        return await NotificationService(context: context)
            .refresh(promptForPermission: promptForNotifications)
    }

    private func refreshWidget(at now: Date, isStopped: @Sendable () -> Bool) -> Bool {
        guard !stop(isStopped) else {
            return false
        }

        return WidgetSnapshotService(context: context).refresh(at: now) != nil
    }

    /// Advances the diagnostics watermark. Deliberately the last stage: a cancelled run must not
    /// make the UI claim maintenance happened when most of it was skipped.
    private func recordRun(at date: Date, isStopped: @Sendable () -> Bool) {
        guard !stop(isStopped) else {
            return
        }

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
