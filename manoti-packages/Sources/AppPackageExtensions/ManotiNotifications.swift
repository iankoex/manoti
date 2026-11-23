//
//  ManotiNotifications.swift
//  AppPackageExtensions
//

import Foundation

nonisolated extension Notification.Name {
    /// Posted after any service persists a change, so screens can refetch.
    public static let manotiDataChanged = Notification.Name("com.iankoex.manoti.dataChanged")
}

public enum ManotiNotifications {
    public static func postDataChanged() {
        NotificationCenter.default.post(name: .manotiDataChanged, object: nil)
    }
}
