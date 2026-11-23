//
//  LoanDirection.swift
//  AppModels
//

import Foundation

nonisolated public enum LoanDirection: String, CaseIterable, Codable, Sendable, Identifiable {
    case lent
    case borrowed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .lent: "Lent"
            case .borrowed: "Borrowed"
        }
    }

    public var symbolName: String {
        switch self {
            case .lent: "arrow.up.right"
            case .borrowed: "arrow.down.left"
        }
    }
}
