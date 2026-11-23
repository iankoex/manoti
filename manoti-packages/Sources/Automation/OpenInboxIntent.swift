//
//  OpenInboxIntent.swift
//  Automation
//

import AppIntents
import Foundation

/// Opens Manoti on the Inbox tab.
///
/// The intent runs in the foreground, leaves a pending route behind and lets `ContentView` perform the
/// navigation. Writing a route instead of touching UIKit keeps the intent portable and testable.
public struct OpenInboxIntent: AppIntent {
    /// Keep in sync with the key observed by `ContentView`.
    static let pendingRouteKey = "manoti.pendingRoute"
    static let inboxRoute = "inbox"

    public static let title: LocalizedStringResource = "Open Inbox"
    public static let description = IntentDescription(
        "Opens Manoti's Inbox so you can review messages that are waiting for a decision."
    )

    public static var supportedModes: IntentModes {
        .foreground
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            UserDefaults.standard.set(Self.inboxRoute, forKey: Self.pendingRouteKey)
        }
        return .result()
    }
}
