//
//  RuleService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

@Observable
public final class RuleService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func save() throws {
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func isValid(pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// Everything the editor knows how to check before a rule is saved.
    ///
    /// Duplicate detection is exact after collapsing whitespace and case: two patterns that
    /// differ only in spacing or case are the same rule. Semantic overlap (two different
    /// patterns matching the same message) is surfaced by `collisionWarnings()` instead,
    /// because rule order deliberately decides those.
    public func validationMessage(
        name: String,
        pattern: String,
        fieldPatterns: [String: String] = [:],
        in ruleSet: ParseRuleSet,
        excluding rule: ParseRule?
    ) throws -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Give the rule a name."
        }

        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Add a pattern."
        }

        guard isValid(pattern: pattern) else {
            return "This pattern is not a valid regular expression."
        }

        let capturesAmount =
            pattern.contains("(?<amount>")
            || fieldPatterns.values.contains { $0.contains("(?<amount>") }
        guard capturesAmount else {
            return "This rule does not capture an amount, so it can never record a payment."
        }

        let sets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let others = sets.flatMap { $0.rules ?? [] }.filter { $0.id != rule?.id }

        if others.contains(where: {
            $0.ruleSet?.id == ruleSet.id
                && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            return "Another rule in this set is already called “\(trimmedName)”."
        }

        let normalised = ParserService.normalisedPattern(pattern)
        if let duplicate = others.first(where: {
            ParserService.normalisedPattern($0.pattern) == normalised
        }) {
            return "This pattern is already used by “\(duplicate.name)”."
        }

        return nil
    }

    /// Duplicate and overlap checks across every enabled rule.
    ///
    /// A message can match more than one pattern; the first rule in priority order wins.
    /// These warnings make that ambiguity visible instead of silently hiding it.
    public func collisionWarnings() throws -> [String] {
        let sets = try context.fetch(
            FetchDescriptor<ParseRuleSet>(sortBy: [SortDescriptor(\ParseRuleSet.priority)])
        )
        let rules = sets.filter(\.isEnabled).flatMap(\.orderedRules)
        var warnings: [String] = []

        var seenPatterns: [String: String] = [:]
        for rule in rules {
            let key = ParserService.normalisedPattern(rule.pattern)
            if let existing = seenPatterns[key] {
                warnings.append("“\(rule.name)” uses the same pattern as “\(existing)”.")
            } else {
                seenPatterns[key] = rule.name
            }
        }

        for rule in rules {
            let sample = rule.sampleText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sample.isEmpty else {
                continue
            }

            let text = ParserService.normaliseForHash(sample)
            let matching = rules.filter {
                ParserService.captureGroups(pattern: $0.pattern, text: text) != nil
            }
            guard matching.count > 1 else {
                continue
            }

            let others = matching.map(\.name).filter { $0 != rule.name }
            guard !others.isEmpty else {
                continue
            }

            let names = others.map { "“\($0)”" }.joined(separator: ", ")
            warnings.append(
                "The sample for “\(rule.name)” also matches \(names). The first rule in priority order wins."
            )
        }

        var unique: [String] = []
        for warning in warnings where !unique.contains(warning) {
            unique.append(warning)
        }

        return unique
    }
}
