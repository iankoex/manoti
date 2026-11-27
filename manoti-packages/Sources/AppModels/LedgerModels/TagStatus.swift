//
//  TagStatus.swift
//  AppModels
//

import Foundation

nonisolated public enum TagStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case open
    case closed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .open: "Open"
            case .closed: "Closed"
        }
    }
}
