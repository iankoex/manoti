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

            await AppMaintenance(context: container.mainContext)
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
