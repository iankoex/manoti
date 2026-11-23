//
//  PrivacyScenePhase.swift
//  AppServices
//

/// The scene phases that affect amount privacy, without importing SwiftUI into the service layer.
public enum PrivacyScenePhase: Sendable {
    case active
    case inactive
    case background
}
