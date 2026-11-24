//
//  RuleValidationTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Rule validation")
struct RuleValidationTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    @discardableResult
    private func addRule(
        _ name: String,
        pattern: String,
        sample: String = "",
        to ruleSet: ParseRuleSet,
        in context: ModelContext
    ) -> ParseRule {
        let rule = ParseRule(name: name, messageType: .expense, pattern: pattern, sampleText: sample)
        rule.ruleSet = ruleSet
        context.insert(rule)
        return rule
    }

    @Test("A rule without an amount capture cannot be saved")
    func amountCaptureIsRequired() throws {
        let context = try makeContext()
        let service = RuleService(context: context)
        let set = ParseRuleSet(name: "Mine", senderMatchers: "*", priority: 0)
        context.insert(set)

        let message = try service.validationMessage(
            name: "Hello",
            pattern: "^HELLO",
            in: set,
            excluding: nil
        )

        #expect(message == "This rule does not capture an amount, so it can never record a payment.")
    }

    @Test("A pattern already used by another rule is refused")
    func duplicatePatternIsRefused() throws {
        let context = try makeContext()
        let service = RuleService(context: context)
        let first = ParseRuleSet(name: "First", senderMatchers: "*", priority: 0)
        let second = ParseRuleSet(name: "Second", senderMatchers: "*", priority: 1)
        context.insert(first)
        context.insert(second)
        addRule("Existing", pattern: #"PAID\s+(?<amount>KES [\d,]+)"#, to: first, in: context)

        let message = try service.validationMessage(
            name: "Another",
            // Same rule, different case.
            pattern: #"paid\s+(?<amount>KES [\d,]+)"#,
            in: second,
            excluding: nil
        )

        #expect(message == "This pattern is already used by “Existing”.")
    }

    @Test("Two rules in one set cannot share a name")
    func duplicateNameIsRefused() throws {
        let context = try makeContext()
        let service = RuleService(context: context)
        let set = ParseRuleSet(name: "Mine", senderMatchers: "*", priority: 0)
        context.insert(set)
        addRule("Cash deposit", pattern: #"DEPOSIT (?<amount>KES [\d,]+)"#, to: set, in: context)

        let message = try service.validationMessage(
            name: "  cash deposit ",
            pattern: #"CASH (?<amount>KES [\d,]+)"#,
            in: set,
            excluding: nil
        )

        #expect(message == "Another rule in this set is already called “cash deposit”.")
    }

    @Test("A valid rule passes every check")
    func validRulePasses() throws {
        let context = try makeContext()
        let service = RuleService(context: context)
        let set = ParseRuleSet(name: "Mine", senderMatchers: "*", priority: 0)
        context.insert(set)

        let message = try service.validationMessage(
            name: "New rule",
            pattern: #"PAID TO (?<payee>.+?) (?<amount>KES [\d,]+)"#,
            in: set,
            excluding: nil
        )

        #expect(message == nil)
    }

    @Test("Two different patterns that match one sample are reported as a collision")
    func sampleCollisionIsReported() throws {
        let context = try makeContext()
        let service = RuleService(context: context)
        let set = ParseRuleSet(name: "Mine", senderMatchers: "*", priority: 0)
        context.insert(set)

        addRule(
            "Narrow",
            pattern: #"^ABC (?<amount>KES [\d,]+)"#,
            sample: "ABC KES 100",
            to: set,
            in: context
        )
        addRule(
            "Broad",
            pattern: #"KES (?<amount>[\d,]+)"#,
            to: set,
            in: context
        )

        let warnings = try service.collisionWarnings()

        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("also matches") == true)
        #expect(warnings.first?.contains("Broad") == true)
    }
}
