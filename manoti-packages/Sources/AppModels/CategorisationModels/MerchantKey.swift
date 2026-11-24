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

    /// The words that identify a merchant, after normalising.
    public static func tokens(_ payee: String) -> Set<String> {
        Set(
            normalise(payee)
                .split(separator: " ")
                .map(String.init)
        )
    }

    /// How much two payees share, scaled by the longer one.
    ///
    /// Two shared words are required so that a single common word ("uber", "shell")
    /// never pulls a different merchant into a match. An identical key scores zero:
    /// exact matches take the exact path and must not also appear as "similar".
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = tokens(lhs)
        let right = tokens(rhs)
        guard !left.isEmpty, !right.isEmpty, left != right else {
            return 0
        }

        let shared = left.intersection(right).count
        guard shared >= 2 else {
            return 0
        }

        return Double(shared) / Double(max(left.count, right.count))
    }
}
