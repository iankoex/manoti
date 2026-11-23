//
//  InvestmentType.swift
//  AppModels
//

import Foundation

nonisolated public enum InvestmentType: String, CaseIterable, Codable, Sendable, Identifiable {
    case moneyMarket
    case treasuryBond
    case treasuryBill

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .moneyMarket: "Money market"
            case .treasuryBond: "Treasury bond"
            case .treasuryBill: "Treasury bill"
        }
    }

    public var symbolName: String {
        switch self {
            case .moneyMarket: "building.columns"
            case .treasuryBond: "doc.text"
            case .treasuryBill: "doc.plaintext"
        }
    }

    public var isCouponPaying: Bool {
        self == .treasuryBond
    }
}
