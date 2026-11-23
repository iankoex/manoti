//
//  Currency.swift
//  AppModels
//

import Foundation

/// An ISO currency with the number of decimal digits it stores.
nonisolated public struct Currency: Hashable, Sendable, Codable, Identifiable {
    public let code: String
    public let exponent: Int

    public var id: String { code }

    public init(code: String, exponent: Int) {
        self.code = code.uppercased()
        self.exponent = max(0, exponent)
    }
}

nonisolated extension Currency {
    static let kes = Currency(code: "KES", exponent: 2)
    static let usd = Currency(code: "USD", exponent: 2)
}
