//
//  OpenReconcileIntent.swift
//  Automation
//

import AppIntents
import Foundation

/// Opens Manoti's reconciliation review screen.
///
/// Leaves a pending route behind and lets `ContentView` present the screen, matching
/// `OpenInboxIntent`.
public struct OpenReconcileIntent: AppIntent {
    /// Keep in sync with the key observed by `ContentView`.
    static let pendingRouteKey = "manoti.pendingRoute"
    static let reconcileRoute = "reconcile"

    public static let title: LocalizedStringResource = "Review Reconciliation"
    public static let description = IntentDescription(
        "Opens Manoti's reconciliation screen to review the latest run."
    )

    public static var supportedModes: IntentModes {
        .foreground
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            UserDefaults.standard.set(Self.reconcileRoute, forKey: Self.pendingRouteKey)
        }
        return .result()
    }
}
