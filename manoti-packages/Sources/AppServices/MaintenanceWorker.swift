//
//  MaintenanceWorker.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

/// Runs the maintenance pipeline on a private background `ModelContext`.
///
/// `BGTaskScheduler` delivers a launch handler on a BackgroundTasks queue, never on the main
/// actor. Running the pipeline through this actor keeps every store read and write on the
/// worker's own executor, so background maintenance never depends on the main actor being free
/// and never blocks the UI.
///
/// Each instance owns one context and executes its work serially. Create one per background run;
/// the foreground keeps using `AppMaintenance` with the container's main context.
@ModelActor
public actor MaintenanceWorker {
    /// Runs the complete post-write pipeline off the main actor.
    @discardableResult
    public func runAfterWrite(
        promptForNotifications: Bool = false,
        now: Date = Date(),
        isStopped: @Sendable () -> Bool = { Task.isCancelled }
    ) async -> MaintenanceReport {
        await MaintenancePipeline(context: modelContext)
            .runAfterWrite(
                promptForNotifications: promptForNotifications,
                now: now,
                isStopped: isStopped
            )
    }

    /// Replays messages parked by a Shortcut without touching notifications.
    @discardableResult
    public func drainPendingMessages() -> Int {
        MaintenancePipeline(context: modelContext).drainPendingMessages()
    }
}
