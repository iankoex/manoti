//
//  ParseRuleSet.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class ParseRuleSet {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Stable identity for seeding; renaming the set never duplicates it.
    public var seedKey: String = ""
    /// Comma-separated sender fragments. `*` matches any sender.
    public var senderMatchers: String = "*"
    public var priority: Int = 0
    public var isEnabled: Bool = true
    public var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ParseRule.ruleSet)
    public var rules: [ParseRule]?

    public init(name: String, seedKey: String = "", senderMatchers: String, priority: Int = 0) {
        self.id = UUID()
        self.name = name
        self.seedKey = seedKey
        self.senderMatchers = senderMatchers
        self.priority = priority
    }

    public var senderMatcherList: [String] {
        senderMatchers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }

    public var orderedRules: [ParseRule] {
        (rules ?? [])
            .filter(\.isEnabled)
            .sorted { $0.priority < $1.priority }
    }

    public func matches(sender: String?) -> Bool {
        let matchers = senderMatcherList
        guard !matchers.isEmpty else {
            return true
        }

        if matchers.contains("*") {
            return true
        }

        guard let sender, !sender.isEmpty else {
            return false
        }

        let normalised = sender.uppercased()
        return matchers.contains { normalised.contains($0) }
    }
}
