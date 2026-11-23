//
//  AccountKind.swift
//  AppModels
//

import Foundation

nonisolated public enum AccountKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case bank
    case mobileMoney
    case cash
    case card

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .bank: "Bank account"
            case .mobileMoney: "Mobile money"
            case .cash: "Cash"
            case .card: "Card"
        }
    }
}
