//
//  ParserService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

/// Reads bank and mobile-money messages using the stored, editable rule sets.
@Observable
nonisolated public final class ParserService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func ruleSets() throws -> [ParseRuleSet] {
        try context.fetch(
            FetchDescriptor<ParseRuleSet>(sortBy: [SortDescriptor(\ParseRuleSet.priority)])
        )
    }

    public func parse(text: String, sender: String? = nil, receivedAt: Date = Date()) throws -> ParseOutcome {
        let sets = try ruleSets()
        return ParserService.parse(text: text, sender: sender, receivedAt: receivedAt, ruleSets: sets)
    }

    /// Pure path used by tests and the rule playground.
    public static func parse(
        text: String,
        sender: String?,
        receivedAt: Date,
        ruleSets: [ParseRuleSet]
    ) -> ParseOutcome {
        let normalised = Normaliser.normalise(text)
        let knownSender = sender?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSender = !(knownSender ?? "").isEmpty

        let ordered = ruleSets.filter(\.isEnabled).sorted { $0.priority < $1.priority }
        let addressable = ordered.filter { $0.matches(sender: knownSender) }

        // A sender is a hint, not a gate. A batch blob has none, and a sender that is not in a
        // rule set (a new bank, a typed literal) must still get the message read. Only when a
        // rule set does claim the sender is the search narrowed to it.
        let candidates = hasSender && !addressable.isEmpty ? addressable : ordered

        for ruleSet in candidates {
            for rule in ruleSet.orderedRules {
                if let parsed = makeMessage(
                    rule: rule,
                    ruleSet: ruleSet,
                    normalised: normalised,
                    rawText: text,
                    sender: sender,
                    receivedAt: receivedAt
                ) {
                    return .parsed(parsed)
                }
            }
        }

        return .unrecognised(rawText: text)
    }

    static func makeMessage(
        rule: ParseRule,
        ruleSet: ParseRuleSet,
        normalised: String,
        rawText: String,
        sender: String?,
        receivedAt: Date
    ) -> ParsedMessage? {
        guard var captures = captureGroups(pattern: rule.pattern, text: normalised) else {
            return nil
        }

        for (field, pattern) in rule.fieldPatterns {
            if let value = firstGroup(pattern: pattern, text: normalised) {
                captures[field] = value
            }
        }

        guard let amountText = captures["amount"],
            let amount = MoneyParser.parse(amountText, defaultCurrency: CurrencyCatalog.defaultCurrency)
        else {
            return nil
        }

        let currency = amount.money.currency
        let feeMinor = MoneyParser.parse(captures["fee"] ?? "", defaultCurrency: currency)?.money.minorUnits ?? 0
        let balanceAfter = MoneyParser.parse(
            captures["balance"] ?? "",
            defaultCurrency: currency
        )?.money.minorUnits

        let dateResult = DateExtractor.extract(
            date: captures["date"],
            time: captures["time"],
            ampm: captures["ampm"],
            fallback: receivedAt
        )

        let payee = FriendlyText.payee(captures["payee"], in: rawText)
        let reference = cleaned(captures["ref"])
        let counterpart = cleaned(captures["counterpart"])

        var confidence = 0.5
        if amount.hadCurrencyToken {
            confidence += 0.2
        } else {
            confidence -= 0.2
        }
        if dateResult.fromMessage {
            confidence += 0.1
        }
        if !reference.isEmpty {
            confidence += 0.15
        }
        if !payee.isEmpty {
            confidence += 0.05
        }
        confidence = min(1, max(0, confidence))

        return ParsedMessage(
            ruleSetName: ruleSet.name,
            ruleName: rule.name,
            messageType: rule.messageType,
            role: rule.role,
            amountMinor: amount.money.minorUnits,
            currencyCode: currency.code,
            feeMinor: feeMinor,
            payee: payee,
            reference: reference,
            counterpartReference: counterpart,
            accountHint: cleaned(captures["account"]),
            cardLast4: cleaned(captures["cardLast4"]),
            balanceAfterMinor: balanceAfter,
            occurredAt: dateResult.date,
            dateFromMessage: dateResult.fromMessage,
            confidence: confidence,
            rawText: rawText,
            sender: sender ?? ""
        )
    }

    static let captureNames = [
        "amount", "payee", "date", "time", "ampm", "ref", "counterpart",
        "account", "cardLast4", "fee", "balance",
    ]

    static func captureGroups(pattern: String, text: String) -> [String: String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        var values: [String: String] = [:]

        for name in captureNames {
            let captured = match.range(withName: name)
            guard captured.location != NSNotFound, let swiftRange = Range(captured, in: text) else {
                continue
            }

            values[name] = String(text[swiftRange])
        }

        return values
    }

    static func firstGroup(pattern: String, text: String) -> String? {
        captureGroups(pattern: pattern, text: text)?.values.first
    }

    static func cleaned(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whitespace-collapsed, uppercased pattern used only for duplicate detection.
    static func normalisedPattern(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

nonisolated enum Normaliser {
    static func normalise(_ text: String) -> String {
        var value =
            text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")

        value =
            value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.uppercased()
    }
}

nonisolated extension ParserService {
    /// Whitespace-collapsed, lowercased text used only for hashing.
    nonisolated static func normaliseForHash(_ text: String) -> String {
        Normaliser.normalise(text).lowercased()
    }
}

nonisolated enum FriendlyText {
    static func payee(_ value: String?, in rawText: String) -> String {
        let cleaned = ParserService.cleaned(value)
        guard !cleaned.isEmpty else {
            return ""
        }

        let collapsed = rawText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if let range = collapsed.range(of: cleaned, options: [.caseInsensitive, .diacriticInsensitive]) {
            return String(collapsed[range])
        }

        return cleaned.capitalized
    }
}
