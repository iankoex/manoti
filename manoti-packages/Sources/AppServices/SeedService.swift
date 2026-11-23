//
//  SeedService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

/// Creates the starter taxonomy and the single settings row exactly once.
@Observable
public final class SeedService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func seedIfNeeded(displayCurrencyCode: String = CurrencyCatalog.defaultCurrency.code) throws {
        try seedSettings(displayCurrencyCode: displayCurrencyCode)
        try seedTaxonomy()
        try migrateCategoryKindsIfNeeded()
        try repairIncomeKindsIfNeeded()
        try seedParseRules()
        try seedSmartRules()
        try refreshBrandNeutralNames()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    private func seedSettings(displayCurrencyCode: String) throws {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if try context.fetch(descriptor).isEmpty {
            let settings = AppSettings()
            settings.displayCurrencyCode = displayCurrencyCode
            context.insert(settings)
        }
    }

    private func seedTaxonomy() throws {
        let existing = try context.fetch(FetchDescriptor<CategoryGroup>())

        // Adopt groups seeded before stable keys existed, so a renamed starter cannot
        // produce a second copy of the whole group.
        for group in existing where group.seedKey.isEmpty {
            if let seed = StarterTaxonomy.groups.first(where: {
                $0.name.caseInsensitiveCompare(group.name) == .orderedSame
            }) {
                group.seedKey = seed.key
            }
        }

        let existingKeys = Set(existing.map(\.seedKey))

        for (index, seed) in StarterTaxonomy.groups.enumerated() where !existingKeys.contains(seed.key) {
            let group = CategoryGroup(
                name: seed.name,
                symbolName: seed.symbolName,
                colorHex: seed.colorHex,
                sortIndex: index
            )
            group.seedKey = seed.key
            context.insert(group)

            for (categoryIndex, categorySeed) in seed.categories.enumerated() {
                let category = SpendingCategory(
                    name: categorySeed.name,
                    symbolName: categorySeed.symbolName,
                    colorHex: seed.colorHex,
                    isFixed: categorySeed.isFixed,
                    keywords: categorySeed.keywords,
                    sortIndex: categoryIndex,
                    kind: seed.kind
                )
                category.group = group
                context.insert(category)
            }
        }
    }

    /// Marks the existing seeded income categories once. New installs already seed the kind;
    /// this pass covers stores created before `kindRaw` existed.
    private func migrateCategoryKindsIfNeeded() throws {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        guard let settings = try context.fetch(descriptor).first,
            !settings.categoryKindsMigrated
        else {
            return
        }

        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let incomeGroupIDs = Set(
            groups
                .filter { $0.seedKey == "income" || $0.name.caseInsensitiveCompare("Income") == .orderedSame }
                .map(\.id)
        )
        let incomeNames: Set<String> = ["Salary", "Business", "Refund", "Gift received", "Other income"]

        for category in try context.fetch(FetchDescriptor<SpendingCategory>()) {
            if let groupID = category.group?.id, incomeGroupIDs.contains(groupID) {
                category.kind = .income
            } else if incomeNames.contains(category.name) {
                category.kind = .income
            }
        }

        settings.categoryKindsMigrated = true
    }

    /// One-time repair for stores that restored an old backup where every category had no
    /// kind and therefore came back as an expense. Income-group categories are income.
    private func repairIncomeKindsIfNeeded() throws {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        guard let settings = try context.fetch(descriptor).first,
            !settings.categoryKindsRepaired
        else {
            return
        }

        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let incomeGroupIDs = Set(
            groups
                .filter { $0.seedKey == "income" || $0.name.caseInsensitiveCompare("Income") == .orderedSame }
                .map(\.id)
        )
        let incomeNames: Set<String> = ["Salary", "Business", "Refund", "Gift received", "Other income"]

        for category in try context.fetch(FetchDescriptor<SpendingCategory>()) where category.kind == .expense {

            if let groupID = category.group?.id, incomeGroupIDs.contains(groupID) {
                category.kind = .income
            } else if incomeNames.contains(category.name) {
                category.kind = .income
            }
        }

        settings.categoryKindsRepaired = true
    }

    private func seedParseRules() throws {
        let existing = try context.fetch(FetchDescriptor<ParseRuleSet>())

        for ruleSet in existing where ruleSet.seedKey.isEmpty {
            if let seed = legacyRuleSetSeed(for: ruleSet.name) {
                ruleSet.seedKey = seed.seedKey
            }
        }

        let existingKeys = Set(existing.map(\.seedKey))

        for seed in StarterParseRules.ruleSets where !existingKeys.contains(seed.seedKey) {
            let ruleSet = ParseRuleSet(
                name: seed.name,
                seedKey: seed.seedKey,
                senderMatchers: seed.senderMatchers,
                priority: seed.priority
            )
            ruleSet.notes = seed.notes
            context.insert(ruleSet)

            for (index, ruleSeed) in seed.rules.enumerated() {
                let rule = ParseRule(
                    name: ruleSeed.name,
                    messageType: ruleSeed.messageType,
                    pattern: ruleSeed.pattern,
                    fieldPatterns: ruleSeed.fieldPatterns,
                    priority: index,
                    sampleText: ruleSeed.sampleText
                )
                rule.ruleSet = ruleSet
                context.insert(rule)
            }
        }
    }

    /// Keeps the seeded display names provider-neutral. Patterns and sender matchers keep the
    /// real values because they must match actual bank messages.
    private func refreshBrandNeutralNames() throws {
        for ruleSet in try context.fetch(FetchDescriptor<ParseRuleSet>()) {
            switch ruleSet.seedKey {
                case "mpesa":
                    ruleSet.name = "Mobile money"
                    ruleSet.notes = "Mobile money confirmations."

                    for rule in ruleSet.rules ?? [] {
                        switch rule.name {
                            case "M-Pesa paid": rule.name = "Paid"
                            case "M-Pesa received from a bank": rule.name = "Received from a bank"
                            case "M-Pesa received": rule.name = "Received"
                            default: break
                        }
                    }

                case "im-bank":
                    ruleSet.name = "Bank"
                    ruleSet.notes = "Bank transaction alerts."

                    for rule in ruleSet.rules ?? [] {
                        switch rule.name {
                            case "Bank to M-Pesa transfer": rule.name = "Bank to mobile money transfer"
                            case "PesaLink received": rule.name = "Bank transfer received"
                            default: break
                        }
                    }

                default:
                    break
            }
        }

        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        if let legacy = categories.first(where: { $0.name == "M-Pesa fees" }),
            !categories.contains(where: { $0.name == "Mobile money fees" })
        {
            legacy.name = "Mobile money fees"
        }
    }

    private func legacyRuleSetSeed(for name: String) -> SeedParseRuleSet? {
        StarterParseRules.ruleSets.first { seed in
            if name.caseInsensitiveCompare(seed.name) == .orderedSame {
                return true
            }

            switch seed.seedKey {
                case "mpesa": return name.caseInsensitiveCompare("Mobile money") == .orderedSame
                case "im-bank": return name.caseInsensitiveCompare("Bank") == .orderedSame
                default: return false
            }
        }
    }

    private func seedSmartRules() throws {
        let existing = try context.fetch(FetchDescriptor<SmartRule>())

        for rule in existing where rule.seedKey.isEmpty {
            if let seed = StarterSmartRules.rules.first(where: { $0.name == rule.name }) {
                rule.seedKey = seed.seedKey
            }
        }

        let existingKeys = Set(existing.map(\.seedKey))
        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())

        for seed in StarterSmartRules.rules where !existingKeys.contains(seed.seedKey) {
            guard
                let category = categories.first(where: {
                    !$0.isArchived
                        && $0.name.caseInsensitiveCompare(seed.targetCategoryName) == .orderedSame
                })
            else {
                continue
            }

            let rule = SmartRule(
                name: seed.name,
                seedKey: seed.seedKey,
                priority: seed.priority,
                conditions: seed.conditions,
                confidenceBoost: seed.confidenceBoost
            )
            rule.targetCategory = category
            context.insert(rule)
        }
    }
}
