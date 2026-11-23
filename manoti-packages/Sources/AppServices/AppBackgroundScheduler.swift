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

/// Best-effort catch-up scheduling. These tasks are opportunistic: they repair missed
/// state, while pre-scheduled local notifications remain the actual delivery mechanism.
@MainActor
public enum AppBackgroundScheduler {
    public static let refreshIdentifier = "com.iankoex.manoti.refresh"
    public static let maintenanceIdentifier = "com.iankoex.manoti.maintenance"

    private static let logger = Logger(subsystem: "com.iankoex.manoti", category: "BackgroundScheduler")
    private static var registered = false

    public static func register(context: ModelContext) {
        guard !registered else {
            return
        }
        registered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            let work = Task { @MainActor in
                await schedule()
                await AppMaintenance(context: context).runAfterWrite(promptForNotifications: false)
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = {
                work.cancel()
                refresh.setTaskCompleted(success: false)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: maintenanceIdentifier,
            using: nil
        ) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            let work = Task { @MainActor in
                await schedule()
                _ = AppMaintenance(context: context).drainAtLaunch()
                await AppMaintenance(context: context).runAfterWrite(promptForNotifications: false)
                processing.setTaskCompleted(success: true)
            }
            processing.expirationHandler = {
                work.cancel()
                processing.setTaskCompleted(success: false)
            }
        }
    }

    public static func schedule() async {
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
#else
/// macOS/tests: no background scheduler.
public enum AppBackgroundScheduler {
    public static func register(context: ModelContext) {}
    public static func schedule() async {}
}
#endif
