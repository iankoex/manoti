//
//  AmountEntry.swift
//  AppModels
//

import Foundation

/// Helpers for free-typed amount fields.
nonisolated public enum AmountEntry {
    /// Keeps a free-typed amount numeric: digits, one decimal separator and, when allowed,
    /// a leading minus. Hardware keyboards and paste can otherwise put letters in a field.
    public static func sanitisedText(
        _ raw: String,
        exponent: Int,
        allowsNegative: Bool = false
    ) -> String {
        var integer = ""
        var fraction = ""
        var sawSeparator = false

        for character in raw {
            if character.isNumber {
                if sawSeparator {
                    fraction.append(character)
                } else {
                    integer.append(character)
                }
            } else if (character == "." || character == ","), exponent > 0, !sawSeparator {
                sawSeparator = true
            }
        }

        var result = integer

        if sawSeparator {
            result = (integer.isEmpty ? "0" : integer) + "." + String(fraction.prefix(exponent))
        }

        if allowsNegative, raw.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
            result = "-" + result
        }

        return result
    }
}
