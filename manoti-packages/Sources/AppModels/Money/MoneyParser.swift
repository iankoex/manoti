//
//  MoneyParser.swift
//  AppModels
//

import Foundation

/// Parses the amount shapes that appear in bank and mobile-money messages, and in
/// free-text amount fields.
///
/// The parser keeps the sign, accepts a currency token before **or** after the number,
/// and treats spaces, non-breaking spaces and thin spaces as thousands separators.
/// Ambiguous shapes are rejected rather than guessed.
nonisolated public enum MoneyParser {
    /// Returns the signed amount and whether the text carried its own currency token.
    public static func parse(
        _ text: String,
        defaultCurrency: Currency = CurrencyCatalog.defaultCurrency
    ) -> (money: Money, hadCurrencyToken: Bool)? {
        let prepared = prepare(text)
        guard !prepared.body.isEmpty else {
            return nil
        }

        let tokenPrefix =
            "(-?)\\s*(" + tokenPattern + ")\\.?\\s*(-?)\\s*(" + numberPattern + ")(?![0-9])"
        if let match = firstMatch(tokenPrefix, in: prepared.body), match.groups.count >= 4,
            let token = match.groups[safe: 1],
            let number = match.groups[safe: 3]
        {
            let currency = currency(forToken: token, fallback: defaultCurrency)
            let negative =
                prepared.negative || !match.groups[0].isEmpty || !match.groups[2].isEmpty

            if let money = signedMoney(number, currency: currency, negative: negative) {
                return (money, true)
            }
        }

        let tokenSuffix = "(-?)\\s*(" + numberPattern + ")\\s*(" + tokenPattern + ")(?![A-Za-z])"
        if let match = firstMatch(tokenSuffix, in: prepared.body), match.groups.count >= 3,
            let number = match.groups[safe: 1],
            let token = match.groups[safe: 2]
        {
            let currency = currency(forToken: token, fallback: defaultCurrency)
            let negative = prepared.negative || !match.groups[0].isEmpty

            if let money = signedMoney(number, currency: currency, negative: negative) {
                return (money, true)
            }
        }

        let bare = "(-?)\\s*(" + numberPattern + ")(?![0-9])"
        if let match = firstMatch(bare, in: prepared.body), match.groups.count >= 2,
            let number = match.groups[safe: 1]
        {
            let negative = prepared.negative || !match.groups[0].isEmpty

            if let money = signedMoney(number, currency: defaultCurrency, negative: negative) {
                return (money, false)
            }
        }

        return nil
    }

    /// Decimal for a rate field, using the same separator rules as money: `7,5` is 7.5,
    /// while `1,234` is one thousand two hundred thirty-four.
    public static func decimalValue(from text: String) -> Decimal? {
        decimal(from: text, exponent: 2)
    }

    /// Converts a numeric run into a decimal. A separator followed by three digits is
    /// read as grouping unless the currency itself uses three decimal places; two or
    /// fewer trailing digits are always a decimal part.
    static func decimal(from raw: String, exponent: Int = 2) -> Decimal? {
        let value =
            raw
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        guard !value.isEmpty else {
            return nil
        }

        let hasDot = value.contains(".")
        let hasComma = value.contains(",")
        var decimalSeparator: Character?

        if hasDot && hasComma {
            let lastDot = value.lastIndex(of: ".") ?? value.startIndex
            let lastComma = value.lastIndex(of: ",") ?? value.startIndex
            let decimal: Character = lastDot > lastComma ? "." : ","
            let grouping: Character = decimal == "." ? "," : "."

            let integerPart = String(value[..<value.firstIndex(of: decimal)!])
            guard groupingIsValid(integerPart, separator: grouping) else {
                return nil
            }

            decimalSeparator = decimal
        } else if hasDot {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if parts.count > 2 {
                guard groupingIsValid(value, separator: ".") else {
                    return nil
                }
            } else {
                let trailingDigits = parts.last?.count ?? 0
                if trailingDigits == 3, exponent != 3 {
                    // `1.234` is one thousand two hundred thirty-four in a two-decimal
                    // currency, but one and 234 thousandths in a three-decimal currency.
                } else if trailingDigits <= 2 || exponent == 3 {
                    decimalSeparator = "."
                } else {
                    return nil
                }
            }
        } else if hasComma {
            let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if parts.count > 2 {
                guard groupingIsValid(value, separator: ",") else {
                    return nil
                }
            } else {
                let trailingDigits = parts.last?.count ?? 0
                if trailingDigits == 3, exponent != 3 {
                    // Thousands grouping, as above.
                } else if trailingDigits <= 2 || exponent == 3 {
                    decimalSeparator = ","
                } else {
                    return nil
                }
            }
        }

        var digits = ""
        var sawDecimal = false

        for character in value {
            if character.isNumber {
                digits.append(character)
            } else if character == decimalSeparator, !sawDecimal {
                digits.append(".")
                sawDecimal = true
            }
        }

        guard !digits.isEmpty else {
            return nil
        }

        return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func currency(forToken token: String, fallback: Currency) -> Currency {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()

        switch trimmed {
            case "KSH", "KSHS", "KES":
                return Currency.kes
            case "$":
                return Currency.usd
            case "£":
                return CurrencyCatalog.currency(for: "GBP")
            case "€":
                return CurrencyCatalog.currency(for: "EUR")
            default:
                return CurrencyCatalog.isKnown(trimmed)
                    ? CurrencyCatalog.currency(for: trimmed) : fallback
        }
    }

    private static func prepare(_ text: String) -> (body: String, negative: Bool) {
        var body =
            text
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2007}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var negative = false
        if body.hasPrefix("("), body.hasSuffix(")") {
            negative = true
            body = String(body.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return (body, negative)
    }

    private static func signedMoney(_ raw: String, currency: Currency, negative: Bool) -> Money? {
        guard let value = decimal(from: raw, exponent: currency.exponent) else {
            return nil
        }

        return Money(decimal: negative ? -value : value, currency: currency)
    }

    private static func groupingIsValid(_ text: String, separator: Character) -> Bool {
        let groups = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard groups.count > 1 else {
            return true
        }

        guard let first = groups.first, (1...3).contains(first.count) else {
            return false
        }

        let rest = groups.dropFirst()
        guard rest.allSatisfy({ (1...3).contains($0.count) }) else {
            return false
        }

        let standard = rest.allSatisfy { $0.count == 3 }
        let indian =
            separator == "," && rest.count >= 2
            && rest.dropLast().allSatisfy { $0.count == 2 }
            && rest.last?.count == 3

        return standard || indian
    }

    private static let numberPattern = "[0-9](?:[0-9.,]| (?=[0-9]))*"

    private static let tokenPattern =
        "(?:KSHS|KSH|KES|USD|EUR|GBP|UGX|TZS|RWF|ZAR|AED|INR|JPY|CNY|CAD|AUD|CHF|KWD|BHD|OMR|TND|JOD|LYD|IQD|\\$|£|€)"

    private static func firstMatch(_ pattern: String, in text: String) -> (
        range: Range<String.Index>, groups: [String]
    )? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange) else {
            return nil
        }

        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if let swiftRange = Range(range, in: text) {
                groups.append(String(text[swiftRange]))
            }
        }

        guard let overall = Range(match.range, in: text) else {
            return nil
        }

        return (overall, groups)
    }
}

extension Array {
    fileprivate nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
