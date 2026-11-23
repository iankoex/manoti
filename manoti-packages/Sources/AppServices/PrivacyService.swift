//
//  PrivacyService.swift
//  AppServices
//

import AppPackageExtensions
import Foundation
import Observation
import UserNotifications

/// In-app amount privacy. The setting persists in `AppSettings`; this service owns the live,
/// session-only state that decides whether monetary figures are masked.
@Observable
public final class PrivacyService: Loggable {
    private let appService: AppService
    private let clearNotifications: @MainActor () -> Void

    /// True while figures are replaced with bullets. Revealing is always an explicit action.
    public private(set) var isAmountsHidden = false

    public init(
        appService: AppService,
        clearNotifications: @escaping @MainActor () -> Void = {}
    ) {
        self.appService = appService
        self.clearNotifications = clearNotifications
        applyLaunchState()
    }

    /// Removes amount-bearing notifications when the user hides figures. Kept injectable so
    /// tests never touch `UNUserNotificationCenter`.
    public static func clearSystemNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Hides on launch only when the user asked Manoti to open with amounts hidden.
    public func applyLaunchState() {
        isAmountsHidden = appService.privacyModeEnabled
    }

    /// Shows every amount until the user hides them again or the scene changes.
    public func reveal() {
        isAmountsHidden = false
    }

    /// Hides amounts now, even when the persistent setting is off. Amount-bearing pending
    /// and delivered notifications are removed so the mask cannot be bypassed from the
    /// lock screen or Notification Center.
    public func hide() {
        isAmountsHidden = true
        clearNotifications()
    }

    /// Inactive and background scenes re-hide when the persistent setting is on. Becoming active
    /// never reveals automatically.
    public func scenePhaseChanged(_ phase: PrivacyScenePhase) {
        guard appService.privacyModeEnabled else {
            return
        }

        switch phase {
            case .active: break
            case .inactive, .background: hide()
        }
    }
}
