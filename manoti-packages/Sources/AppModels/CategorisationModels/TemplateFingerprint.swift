//
//  TemplateFingerprint.swift
//  AppModels
//

import Foundation

/// A stable identity for a message's shape, safe to keep when raw text is not.
///
/// Every run of digits and amount punctuation becomes `#`, so "balance is KES 1,204.00"
/// and "balance is KES 980.00" collapse to one template. The sender keeps otherwise
/// unrelated banks apart.
nonisolated public enum TemplateFingerprint {
    /// AM, PM, a.m. and p.m. say nothing about the message's shape. The negative
    /// lookahead keeps words like "amazing" intact.
    private static let meridiem = "(?i)\\b([ap])\\.?m\\.?(?![a-z])"

    private static let digitRun = "[0-9][0-9.,:/-]*"

    public static func make(sender: String?, text: String) -> String {
        let normalisedSender = (sender ?? "")
            .uppercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let masked = maskReferences(in: text)
            .replacingOccurrences(of: meridiem, with: "#", options: .regularExpression)
            .replacingOccurrences(of: digitRun, with: "#", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return "\(normalisedSender)|\(masked)"
    }

    /// Replaces reference-like tokens with `#`.
    ///
    /// A bank reference mixes random letters and digits ("UKL6H2AF65"); the letters carry
    /// no signal, so the token's position identifies the shape. A currency amount has one
    /// letter-to-digit switch at most ("Ksh1,510"), so requiring at least two switches
    /// leaves amounts and merchant names alone.
    private static func maskReferences(in text: String) -> String {
        var result = ""
        var run = ""

        func flushRun() {
            guard !run.isEmpty else {
                return
            }

            result += isReferenceLike(run) ? "#" : run
            run = ""
        }

        for character in text {
            if character.isLetter || character.isNumber {
                run.append(character)
            } else {
                flushRun()
                result.append(character)
            }
        }

        flushRun()
        return result
    }

    private static func isReferenceLike(_ run: String) -> Bool {
        guard run.count >= 6 else {
            return false
        }

        let digitCount = run.filter(\.isNumber).count
        let letterCount = run.count - digitCount

        guard digitCount >= 2, letterCount >= 2 else {
            return false
        }

        var switches = 0
        var previousWasDigit: Bool?

        for character in run {
            let isDigit = character.isNumber

            if let previousWasDigit, previousWasDigit != isDigit {
                switches += 1
            }

            previousWasDigit = isDigit
        }

        return switches >= 2
    }
}
