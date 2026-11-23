//
//  InvestmentCashFlowKind.swift
//  AppModels
//

import Foundation

nonisolated public enum InvestmentCashFlowKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case purchase
    case coupon
    case redemption
    case tax
    case interest
    case contribution
    case withdrawal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .purchase: "Purchase"
            case .coupon: "Coupon"
            case .redemption: "Redemption"
            case .tax: "Withholding tax"
            case .interest: "Interest"
            case .contribution: "Contribution"
            case .withdrawal: "Withdrawal"
        }
    }

    public var symbolName: String {
        switch self {
            case .purchase: "arrow.up.right"
            case .coupon: "percent"
            case .redemption: "arrow.down.left"
            case .tax: "minus.circle"
            case .interest: "banknote"
            case .contribution: "plus.circle"
            case .withdrawal: "minus.circle"
        }
    }
}
