//
//  AppInfo.swift
//  AppModels
//

import Foundation

/// Static app identity used by Settings, diagnostics and backups.
nonisolated public enum AppInfo {
    public static let name: String = "Manoti"
    /// The backup writer's version marker; the backup schema version lives in `BackupDocument`.
    public static let version: String = "1.0"
}
