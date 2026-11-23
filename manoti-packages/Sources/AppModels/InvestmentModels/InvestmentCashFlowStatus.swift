//
//  InvestmentCashFlowStatus.swift
//  AppModels
//

import Foundation

nonisolated public enum InvestmentCashFlowStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case scheduled
    case paid
    case pending

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .scheduled: "Scheduled"
            case .paid: "Paid"
            case .pending: "Pending"
        }
    }
}
