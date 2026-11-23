//
//  SystemNotificationCenter.swift
//  AppServices
//

import Foundation
import UserNotifications

nonisolated public enum NotificationSchedulingError: Error, Equatable, Sendable {
    case notAuthorized
}

/// Local-notification delivery through `UNUserNotificationCenter`. No remote or push path
/// exists anywhere in Manoti.
@MainActor
public struct SystemNotificationCenter: UserNotificationCentering {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func add(_ request: UNNotificationRequest) async throws {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                throw NotificationSchedulingError.notAuthorized
        }

        try await center.add(request)
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func removePending(identifiers: [String]?) {
        if let identifiers {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        } else {
            center.removeAllPendingNotificationRequests()
        }
    }
}
