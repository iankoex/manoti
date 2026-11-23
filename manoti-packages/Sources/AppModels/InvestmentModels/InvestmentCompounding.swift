//
//  InvestmentCompounding.swift
//  AppModels
//

import Foundation

nonisolated public enum InvestmentCompounding: String, CaseIterable, Codable, Sendable, Identifiable {
    case daily

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .daily: "Daily"
        }
    }
}
