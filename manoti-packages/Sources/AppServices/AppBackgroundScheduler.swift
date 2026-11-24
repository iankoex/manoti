//
//  AppBackgroundScheduler.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

#if os(iOS)
import BackgroundTasks
import OSLog
import Synchronization

/// Best-effort catch-up scheduling. These tasks are opportunistic: they repair missed
/// state, while pre-scheduled local notifications remain the actual delivery mechanism.
@MainActor
public enum AppBackgroundScheduler {
    nonisolated public static let refreshIdentifier = "com.iankoex.manoti.refresh"
    nonisolated public static let maintenanceIdentifier = "com.iankoex.manoti.maintenance"

    nonisolated private static let logger = Logger(
        subsystem: "com.iankoex.manoti",
        category: "BackgroundScheduler"
    )

    /// Whether `BGTaskScheduler` accepted both launch handlers.
    ///
    /// Submitting a request for an identifier that was never registered is a fatal assertion
    /// inside BackgroundTasks, so scheduling is gated on this flag.
    nonisolated private static let canSchedule = Atomic<Bool>(false)

    private static var registered = false

    /// Registers both launch handlers. Must run before the app finishes launching.
    ///
    /// The handlers are declared `@Sendable` on purpose. A plain closure literal written inside
    /// this `@MainActor` function would inherit the main actor and the compiler would emit an
    /// "unexpected executor" precondition at its entry. BackgroundTasks invokes the handler on
    /// its own queue, so that precondition traps the process the first time a task runs. Writing
    /// the type explicitly keeps the closure nonisolated, and `ModelContainer` is `Sendable`, so
    /// the container can be captured without any global mutable state.
    public static func register(container: ModelContainer) {
        guard !registered else {
            return
        }
        registered = true

        let refreshHandler: @Sendable (BGTask) -> Void = { task in
            guard task is BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            run(task, container: container)
        }

        let maintenanceHandler: @Sendable (BGTask) -> Void = { task in
            guard task is BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            run(task, container: container)
        }

        let refreshRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil,
            launchHandler: refreshHandler
        )

        let maintenanceRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: maintenanceIdentifier,
            using: nil,
            launchHandler: maintenanceHandler
        )

        // Registration is only accepted before launch completes. A background App Intent can run
        // before `AppRoot` exists, so the submission path must never assume this succeeded.
        let accepted = refreshRegistered && maintenanceRegistered
        canSchedule.store(accepted, ordering: .releasing)

        if !accepted {
            logger.error("Background task registration was rejected; scheduling is disabled")
        }
    }

    // MARK: - Running a task

    /// Runs one background task and finishes it exactly once.
    ///
    /// Nothing here is main-actor isolated. The work runs on a `MaintenanceWorker`, which owns a
    /// private `ModelContext`, so the store is never touched from the UI context while the app is
    /// in the background.
    nonisolated private static func run(_ task: BGTask, container: ModelContainer) {
        let reference = BackgroundTaskReference(task: task)

        // Expiration and completion race on two different queues. `Atomic` gives an exactly-once
        // guard without a lock, and the flag lets a cancelled run stop between pipeline stages.
        let stopped = Atomic<Bool>(false)
        let completed = Atomic<Bool>(false)

        task.expirationHandler = {
            stopped.store(true, ordering: .relaxed)

            if !completed.exchange(true, ordering: .acquiring) {
                reference.task.setTaskCompleted(success: false)
            }
        }

        let worker = MaintenanceWorker(modelContainer: container)

        Task {
            let report = await worker.runAfterWrite(
                promptForNotifications: false,
                isStopped: { stopped.load(ordering: .relaxed) }
            )

            logger.debug(
                "Background maintenance replayed \(report.outboxDrained, privacy: .public) messages, settled \(report.investmentsSettled, privacy: .public) investments"
            )

            if !completed.exchange(true, ordering: .acquiring) {
                reference.task.setTaskCompleted(success: !stopped.load(ordering: .relaxed))
            }
        }
    }

    // MARK: - Scheduling

    /// Submits the next requests. Safe to call from any isolation domain.
    ///
    /// Does nothing until the handlers are registered: an intent can run in a background launch
    /// before the composition root exists, and BackgroundTasks aborts the process if a request is
    /// submitted for an unregistered identifier.
    nonisolated public static func schedule() async {
        guard canSchedule.load(ordering: .acquiring) else {
            logger.debug("Skipping background scheduling: handlers are not registered yet")
            return
        }

        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try await BGTaskScheduler.shared.submitTaskRequest(refresh)
        } catch {
            logger.debug("Could not schedule app refresh: \(error.localizedDescription, privacy: .public)")
        }

        let maintenance = BGProcessingTaskRequest(identifier: maintenanceIdentifier)
        maintenance.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        maintenance.requiresNetworkConnectivity = false
        maintenance.requiresExternalPower = false

        do {
            try await BGTaskScheduler.shared.submitTaskRequest(maintenance)
        } catch {
            logger.debug("Could not schedule maintenance: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// A `BGTask` that can cross an isolation boundary.
///
/// `BackgroundTasks` hands the launch handler a `BGTask` and expects it to be used from several
/// queues: the launch handler, the expiration handler, and `setTaskCompleted(success:)`. The SDK
/// does not mark the class `Sendable`, so Swift's region-based isolation refuses to hand it to a
/// task, and `sending` cannot apply because the framework keeps its own reference. This wrapper is
/// the single, deliberate escape hatch: it stores one immutable reference and adds no state, so the
/// unchecked conformance cannot be hiding a data race. All mutable state stays in `Atomic` values.
nonisolated struct BackgroundTaskReference: @unchecked Sendable {
    let task: BGTask
}
#else
/// macOS/tests: no background scheduler.
public enum AppBackgroundScheduler {
    public static func register(container: ModelContainer) {}
    public static func schedule() async {}
}
#endif
