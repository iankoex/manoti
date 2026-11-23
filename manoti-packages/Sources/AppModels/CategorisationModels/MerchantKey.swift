//
//  MerchantKey.swift
//  AppModels
//

import Foundation

nonisolated public enum MerchantKey {
    private static let noise: Set<String> = [
        "limited", "ltd", "co", "company", "enterprises", "services", "service", "the",
    ]

    /// Lowercased words only, with common corporate noise removed.
    public static func normalise(_ payee: String) -> String {
        payee
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty && !noise.contains($0) }
            .joined(separator: " ")
    }
}
