//
//  ManotiAppDelegate.swift
//  Manoti
//

#if os(iOS)
import AppModels
import AppServices
import CloudKit
import SwiftData
import SwiftUI

/// Handles CloudKit's silent push and installs the best-effort database subscription.
///
/// The subscription only covers changes synced from another device. It never replaces
/// local scheduling: Shortcut writes schedule their own notifications immediately.
final class ManotiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register here rather than in the composition root: a background App Intent can run
        // before `AppRoot` is constructed, and BackgroundTasks rejects handlers registered after
        // launch completes. Registration is idempotent, so AppRoot may still call it.
        if let container = AppStore.container() {
            AppBackgroundScheduler.register(container: container)
        }

        Task { await ManotiCloudSubscriptions.installIfNeeded() }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let container = AppStore.container() else {
                completionHandler(.noData)
                return
            }

            // A silent push can arrive while the app is inactive, so run the pipeline on a
            // private background context instead of the main one.
            await MaintenanceWorker(modelContainer: container)
                .runAfterWrite(promptForNotifications: false)
            completionHandler(.newData)
        }
    }
}

@MainActor
enum ManotiCloudSubscriptions {
    private static let installedKey = "manoti.cloudSubscription.v1"

    static func installIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: installedKey) else {
            return
        }

        let container = CKContainer(identifier: AppStore.cloudKitContainerID)
        let subscription = CKDatabaseSubscription(subscriptionID: "manoti-database-changes")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await container.privateCloudDatabase.save(subscription)
            UserDefaults.standard.set(true, forKey: installedKey)
        } catch {
            // No iCloud account, or a transient failure. Try again next launch.
        }
    }
}
#endif
