//
//  ManotiAppTargetShortcuts.swift
//  Manoti
//

import AppIntents
import Automation

/// The App Shortcuts the system registers for the app.
///
/// Xcode 27's App Intents metadata processor only extracts `AppShortcut` declarations made in the app
/// target: a provider inside a Swift package compiles, but its shortcuts are left out of
/// `Metadata.appintents`. This provider is therefore the single source of truth; do not add a mirror
/// in the package. The package-level `AppShortcutsTests` checks this file stays within the ten-shortcut
/// limit rather than duplicating the definitions.
struct ManotiAppTargetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense in \(.applicationName)",
            ],
            shortTitle: "Log Payment",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: MarkContextIntent(),
            phrases: [
                "Mark a ride in \(.applicationName)"
            ],
            shortTitle: "Mark Ride",
            systemImageName: "car"
        )

        AppShortcut(
            intent: OpenInboxIntent(),
            phrases: [
                "Open my Inbox in \(.applicationName)",
                "Open Inbox in \(.applicationName)",
            ],
            shortTitle: "Open Inbox",
            systemImageName: "tray"
        )

        AppShortcut(
            intent: OpenReconcileIntent(),
            phrases: [
                "Review reconciliation in \(.applicationName)",
                "Open reconciliation in \(.applicationName)",
            ],
            shortTitle: "Review Reconciliation",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }
}
