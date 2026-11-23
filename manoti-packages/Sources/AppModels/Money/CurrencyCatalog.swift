//
//  CurrencyCatalog.swift
//  AppModels
//

import Foundation

/// Supported currencies. Exponents are code, never user data: changing one would
/// silently rescale every stored amount for that currency.
nonisolated public enum CurrencyCatalog {
    public static let defaultCurrency = Currency.kes

    public static let supported: [Currency] = [
        Currency(code: "KES", exponent: 2),
        Currency(code: "USD", exponent: 2),
        Currency(code: "EUR", exponent: 2),
        Currency(code: "GBP", exponent: 2),
        Currency(code: "UGX", exponent: 0),
        Currency(code: "TZS", exponent: 2),
        Currency(code: "RWF", exponent: 0),
        Currency(code: "ZAR", exponent: 2),
        Currency(code: "AED", exponent: 2),
        Currency(code: "INR", exponent: 2),
        Currency(code: "JPY", exponent: 0),
        Currency(code: "CNY", exponent: 2),
        Currency(code: "CAD", exponent: 2),
        Currency(code: "AUD", exponent: 2),
        Currency(code: "CHF", exponent: 2),
        Currency(code: "KWD", exponent: 3),
        Currency(code: "BHD", exponent: 3),
        Currency(code: "OMR", exponent: 3),
        Currency(code: "TND", exponent: 3),
        Currency(code: "JOD", exponent: 3),
        Currency(code: "LYD", exponent: 3),
        Currency(code: "IQD", exponent: 3),
    ]

    public static func currency(for code: String) -> Currency {
        let normalised = normalizedCode(code)

        if let match = supported.first(where: { $0.code == normalised }) {
            return match
        }

        return Currency(code: normalised, exponent: 2)
    }

    /// True when the code has a declared exponent. Unknown codes still resolve to a
    /// two-decimal currency so a hand-edited backup stays readable, but callers that
    /// write money can reject them.
    public static func isKnown(_ code: String) -> Bool {
        supported.contains { $0.code == normalizedCode(code) }
    }

    private static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
