//
//  AppMaintenance.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

/// The foreground face of the post-write pipeline.
///
/// Keeping the work out of the view tree is what makes background Shortcut writes schedule
/// notifications and refresh the widget when Manoti is not open. This type owns the main
/// context and the diagnostics the UI observes; the work itself lives in `MaintenancePipeline`,
/// which a `BGTask` runs on a private context through `MaintenanceWorker`.
@Observable
@MainActor
public final class AppMaintenance: Loggable {
    public typealias Report = MaintenanceReport

    private let context: ModelContext
    public private(set) var lastRunAt: Date?
    public private(set) var lastReport: MaintenanceReport?

    public init(context: ModelContext) {
        self.context = context
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            lastRunAt = settings.lastMaintenanceAt
        }
    }

    /// Runs the complete post-write pipeline. Safe to call from every intent and every save.
    @discardableResult
    public func runAfterWrite(promptForNotifications: Bool = false, now: Date = Date()) async
        -> MaintenanceReport
    {
        let report = await MaintenancePipeline(context: context)
            .runAfterWrite(promptForNotifications: promptForNotifications, now: now)

        lastRunAt = report.ranAt
        lastReport = report
        return report
    }

    /// Drains parked messages without touching notifications. Used at launch before the
    /// first frame, where awaiting the full pipeline is not possible.
    @discardableResult
    public func drainAtLaunch() -> Int {
        MaintenancePipeline(context: context).drainPendingMessages()
    }
}
