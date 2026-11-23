//
//  UserNotificationCentering.swift
//  AppServices
//

import Foundation
import UserNotifications

/// The small slice of `UNUserNotificationCenter` the service needs. A fake lets tests verify
/// scheduling without touching the system notification daemon.
@MainActor
public protocol UserNotificationCentering {
    func requestAuthorization() async -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String]?)
}
