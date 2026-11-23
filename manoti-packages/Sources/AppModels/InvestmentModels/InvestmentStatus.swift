//
//  InvestmentStatus.swift
//  AppModels
//

import Foundation

nonisolated public enum InvestmentStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case pending
    case active
    case matured

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .pending: "Pending settlement"
            case .active: "Active"
            case .matured: "Matured"
        }
    }

    public var symbolName: String {
        switch self {
            case .pending: "clock"
            case .active: "checkmark.circle"
            case .matured: "flag.checkered"
        }
    }
}
