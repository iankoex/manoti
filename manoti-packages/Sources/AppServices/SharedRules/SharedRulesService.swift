//
//  SharedRulesService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

/// The shape of `regex-rules.json`. The file ships inside the app and is also served from
/// the repository, so rules can be corrected with an app update or without one.
nonisolated public struct SharedRuleDocument: Decodable, Sendable {
    public let version: Int
    /// Monotonic content revision. Not the schema `version`.
    public let revision: Int?
    public let rules: [SharedRule]
}

nonisolated public struct SharedRule: Decodable, Sendable {
    public let key: String
    public let name: String
    public let type: String
    public let pattern: String
    public let fieldPatterns: [String: String]?
    public let sample: String?
}

nonisolated public struct SharedRulesUpdate: Sendable {
    public let ruleCount: Int
    public let skippedCount: Int
    /// True when the database already had rules and an app update advanced them.
    public let shouldNotify: Bool
    public let ruleSetName: String
}

nonisolated public enum SharedRulesError: LocalizedError, Equatable {
    case missingBundledRules
    case tooLarge
    case unsupportedVersion(Int)
    case duplicateKey(String)
    case invalidRule(String)
    case invalidPattern(String)

    public var errorDescription: String? {
        switch self {
            case .missingBundledRules:
                return "The rules that come with Manoti are missing. Reinstall the app."
            case .tooLarge:
                return "The rules file is too large."
            case .unsupportedVersion(let version):
                return "This rules file needs a newer version of Manoti (file version \(version))."
            case .duplicateKey(let key):
                return "The rules file uses the key “\(key)” more than once."
            case .invalidRule(let detail):
                return "The rules file is invalid: \(detail)."
            case .invalidPattern(let name):
                return "The rules file has an invalid pattern in “\(name)”."
        }
    }
}

/// Installs the shared rule file that ships inside the app. It is applied at launch when its
/// revision is newer, so every app update carries its rule changes into the local store.
///
/// Rules go into their own rule set, so the seeded and hand-edited rule sets are never
/// touched. The whole document is validated before a single rule is written, and the
/// previous rules survive an invalid file.
@Observable
public final class SharedRulesService: Loggable {
    public static let ruleSetName = "Updates"
    public static let ruleSetSeedKey = "remote"
    public static let supportedVersion = 1
    public static let revisionKey = "manoti.rulesRevision"

    private static let maximumBytes = 256 * 1024
    private static let maximumRules = 200
    private static let maximumPatternLength = 4_096
    private static let maximumFieldPatterns = 32

    private let context: ModelContext
    private let defaults: UserDefaults

    public init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    /// The rule file compiled into the app.
    public static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "regex-rules", withExtension: "json") else {
            throw SharedRulesError.missingBundledRules
        }

        return try Data(contentsOf: url)
    }

    /// Applies the bundled file when it is newer than the installed one, or when the set was
    /// removed. Called at launch, so an app update carries its new rules into the local store.
    public func installBundledRulesIfNeeded() throws -> SharedRulesUpdate? {
        let document = try decode(Self.bundledData())
        let revision = document.revision ?? 0
        let appliedRevision = defaults.integer(forKey: Self.revisionKey)
        let hadAppliedRules = defaults.object(forKey: Self.revisionKey) != nil

        let hasRuleSet = try context.fetch(FetchDescriptor<ParseRuleSet>())
            .contains { $0.seedKey == Self.ruleSetSeedKey }

        guard revision > appliedRevision || !hasRuleSet else {
            return nil
        }

        let update = try install(document)
        return SharedRulesUpdate(
            ruleCount: update.ruleCount,
            skippedCount: update.skippedCount,
            // Stay quiet on a fresh install; speak up when an app update changed rules.
            shouldNotify: hadAppliedRules && update.ruleCount > 0,
            ruleSetName: update.ruleSetName
        )
    }

    /// Validates the whole document first, then replaces the shared rule set in one save.
    public func install(_ data: Data) throws -> SharedRulesUpdate {
        try install(decode(data))
    }

    private func install(_ document: SharedRuleDocument) throws -> SharedRulesUpdate {
        var keys: Set<String> = []
        var names: Set<String> = []
        var patterns: Set<String> = []

        for rule in document.rules {
            guard keys.insert(rule.key).inserted else {
                throw SharedRulesError.duplicateKey(rule.key)
            }

            let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(name.uppercased()).inserted else {
                throw SharedRulesError.invalidRule("two rules are named “\(name)”")
            }

            guard patterns.insert(ParserService.normalisedPattern(rule.pattern)).inserted else {
                throw SharedRulesError.invalidRule("two rules use the same pattern")
            }
        }

        let rules = try document.rules.map(validated)
        let update = try apply(rules)

        // Remembering the revision keeps an older bundled file from replacing a newer
        // download on the next launch.
        if let revision = document.revision {
            defaults.set(revision, forKey: Self.revisionKey)
        }

        return update
    }

    private func decode(_ data: Data) throws -> SharedRuleDocument {
        guard data.count <= Self.maximumBytes else {
            throw SharedRulesError.tooLarge
        }

        let document: SharedRuleDocument
        do {
            document = try JSONDecoder().decode(SharedRuleDocument.self, from: data)
        } catch {
            throw SharedRulesError.invalidRule("the file could not be read")
        }

        guard document.version >= 1, document.version <= Self.supportedVersion else {
            throw SharedRulesError.unsupportedVersion(document.version)
        }

        guard document.rules.count <= Self.maximumRules else {
            throw SharedRulesError.tooLarge
        }

        return document
    }

    private struct ValidatedRule {
        let name: String
        let type: LedgerEntryKind
        let pattern: String
        let fieldPatterns: [String: String]
        let sampleText: String
    }

    private func validated(_ rule: SharedRule) throws -> ValidatedRule {
        let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw SharedRulesError.invalidRule("a rule is missing its name")
        }

        guard rule.key.trimmingCharacters(in: .whitespacesAndNewlines) == rule.key,
            !rule.key.isEmpty
        else {
            throw SharedRulesError.invalidRule("“\(name)” has an empty or padded key")
        }

        guard let type = LedgerEntryKind(rawValue: rule.type) else {
            throw SharedRulesError.invalidRule("“\(name)” has an unknown type “\(rule.type)”")
        }

        guard rule.pattern.count <= Self.maximumPatternLength else {
            throw SharedRulesError.invalidRule("“\(name)” has a pattern that is too long")
        }

        guard (try? NSRegularExpression(pattern: rule.pattern)) != nil else {
            throw SharedRulesError.invalidPattern(name)
        }

        let fieldPatterns = rule.fieldPatterns ?? [:]
        guard fieldPatterns.count <= Self.maximumFieldPatterns else {
            throw SharedRulesError.invalidRule("“\(name)” has too many field patterns")
        }

        for (field, pattern) in fieldPatterns {
            guard pattern.count <= Self.maximumPatternLength else {
                throw SharedRulesError.invalidRule("“\(name)” has a \(field) pattern that is too long")
            }

            guard (try? NSRegularExpression(pattern: pattern)) != nil else {
                throw SharedRulesError.invalidPattern("\(name) (\(field))")
            }
        }

        // A rule that cannot produce an amount can never be applied, so catch it here
        // instead of letting it sit in the list and silently do nothing.
        let capturesAmount =
            rule.pattern.contains("(?<amount>")
            || fieldPatterns.values.contains { $0.contains("(?<amount>") }
        guard capturesAmount else {
            throw SharedRulesError.invalidRule("“\(name)” does not capture an amount")
        }

        return ValidatedRule(
            name: name,
            type: type,
            pattern: rule.pattern,
            fieldPatterns: fieldPatterns,
            sampleText: rule.sample ?? ""
        )
    }

    private func apply(_ rules: [ValidatedRule]) throws -> SharedRulesUpdate {
        let ruleSets = try context.fetch(FetchDescriptor<ParseRuleSet>())

        // A user rule that already covers a message wins; never add a second copy of it.
        let userPatterns = Set(
            ruleSets
                .filter { $0.seedKey != Self.ruleSetSeedKey }
                .flatMap { $0.rules ?? [] }
                .map { ParserService.normalisedPattern($0.pattern) }
        )
        let installable = rules.filter {
            !userPatterns.contains(ParserService.normalisedPattern($0.pattern))
        }
        let skippedCount = rules.count - installable.count

        let ruleSet: ParseRuleSet

        if let existing = ruleSets.first(where: { $0.seedKey == Self.ruleSetSeedKey }) {
            ruleSet = existing
            for rule in existing.rules ?? [] {
                context.delete(rule)
            }
        } else {
            ruleSet = ParseRuleSet(
                name: Self.ruleSetName,
                seedKey: Self.ruleSetSeedKey,
                senderMatchers: "*",
                // Tried after the seeded sets, so a downloaded rule never shadows a
                // working built-in rule with the same message.
                priority: 100
            )
            context.insert(ruleSet)
        }

        ruleSet.name = Self.ruleSetName
        ruleSet.notes = "Shared rules that ship with Manoti. They update with the app."
        ruleSet.senderMatchers = "*"
        ruleSet.priority = 100
        ruleSet.isEnabled = true

        for (index, rule) in installable.enumerated() {
            let model = ParseRule(
                name: rule.name,
                messageType: rule.type,
                pattern: rule.pattern,
                fieldPatterns: rule.fieldPatterns,
                priority: index,
                sampleText: rule.sampleText
            )
            model.ruleSet = ruleSet
            context.insert(model)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        ManotiNotifications.postDataChanged()
        return SharedRulesUpdate(
            ruleCount: installable.count,
            skippedCount: skippedCount,
            shouldNotify: false,
            ruleSetName: ruleSet.name
        )
    }
}
