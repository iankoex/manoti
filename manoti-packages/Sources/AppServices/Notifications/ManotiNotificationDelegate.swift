//
//  ManotiNotificationDelegate.swift
//  AppServices
//

import Foundation
import UserNotifications

/// Shows Manoti's local alerts even when the app is already in the foreground.
///
/// Without a delegate, iOS silently drops a notification that fires while the app is
/// active, which made large-transaction and budget alerts depend on backgrounding first.
public final class ManotiNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = ManotiNotificationDelegate()

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
