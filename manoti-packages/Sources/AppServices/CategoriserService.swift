//
//  CategoriserService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

nonisolated public struct CategorySuggestion: Identifiable {
    public let category: SpendingCategory
    public let confidence: Double
    public let reason: String
    /// True only when a `MerchantMemory` for this payee has `autoApply` set. A high
    /// confidence is not permission to file without asking.
    public let isAutoApplicable: Bool

    public var id: UUID { category.id }

    public init(
        category: SpendingCategory,
        confidence: Double,
        reason: String,
        isAutoApplicable: Bool = false
    ) {
        self.category = category
        self.confidence = confidence
        self.reason = reason
        self.isAutoApplicable = isAutoApplicable
    }
}

/// Proposes categories. It never silently files a transaction the user has not taught it.
@Observable
nonisolated public final class CategoriserService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func suggest(
        payee: String,
        amountMinor: Int64,
        date: Date = Date(),
        account: Account? = nil,
        contextMerchant: String? = nil,
        kind: CategoryKind? = nil,
        calendar: Calendar = .current
    ) throws -> [CategorySuggestion] {
        let key = MerchantKey.normalise(payee)
        let hasPayee = !key.isEmpty
        var results: [CategorySuggestion] = []
        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let categories = try fetchCategories()
        let activeContext = contextMerchant ?? activeContextMerchant(at: date)
        let now = Date()

        if hasPayee {
            if let memory = memories.first(where: { $0.merchantKey == key }),
                let category = memory.category,
                isEligible(category, kind: kind)
            {
                results.append(
                    CategorySuggestion(
                        category: category,
                        confidence: memoryConfidence(memory, category: category, now: now),
                        reason:
                            "You filed \(memory.displayName.isEmpty ? payee : memory.displayName) here \(memory.timesSeen) time\(memory.timesSeen == 1 ? "" : "s")",
                        isAutoApplicable: memory.autoApply
                    )
                )

                // A merchant the user files under two categories keeps the other one a
                // tap away, instead of being overwritten on the next confirmation.
                for (categoryID, count) in memory.categoryCounts
                where count >= 2 && categoryID != category.id {
                    guard let alternative = categories.first(where: { $0.id == categoryID }),
                        isEligible(alternative, kind: kind)
                    else {
                        continue
                    }

                    results.append(
                        CategorySuggestion(
                            category: alternative,
                            confidence: 0.6,
                            reason: "Filed here \(count) time\(count == 1 ? "" : "s") before"
                        )
                    )
                }
            }

            for memory in memories where memory.merchantKey != key {
                guard let category = memory.category, isEligible(category, kind: kind) else {
                    continue
                }

                let aliasMatch = (memory.aliases ?? []).contains { $0.aliasKey == key }
                let similar = MerchantKey.similarity(memory.merchantKey, key) >= 0.6

                guard aliasMatch || similar else {
                    continue
                }

                results.append(
                    CategorySuggestion(
                        category: category,
                        confidence: aliasMatch ? 0.85 : 0.8,
                        reason: "Similar merchant: \(memory.displayName)"
                    )
                )
            }
        }

        let rules = try context.fetch(
            FetchDescriptor<SmartRule>(
                predicate: #Predicate<SmartRule> { $0.isEnabled },
                sortBy: [SortDescriptor(\SmartRule.priority)]
            )
        )

        // Highest priority first, first match wins. A later, louder rule must not override it.
        for rule in rules {
            guard let category = rule.targetCategory, isEligible(category, kind: kind) else {
                continue
            }

            if rule.conditions.matches(
                amountMinor: amountMinor,
                payee: payee,
                date: date,
                contextMerchant: activeContext,
                calendar: calendar
            ) {
                results.append(
                    CategorySuggestion(
                        category: category,
                        confidence: min(0.95, 0.6 + rule.confidenceBoost),
                        reason: rule.name
                    )
                )
                break
            }
        }

        if hasPayee {
            let upper = payee.uppercased()

            for category in categories where !category.keywordList.isEmpty {
                guard isEligible(category, kind: kind) else {
                    continue
                }

                if category.keywordList.contains(where: { upper.contains($0.uppercased()) }) {
                    results.append(
                        CategorySuggestion(category: category, confidence: 0.55, reason: "Merchant keyword")
                    )
                }
            }

            if let history = try historySuggestion(for: key, kind: kind) {
                results.append(history)
            }
        }

        return bestPerCategory(results)
    }

    /// Records that the user (or auto-apply) filed a payee under a category.
    public func learn(payee: String, category: SpendingCategory, account: Account? = nil) throws {
        try recordLearning(payee: payee, category: category, account: account)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// Mutates the merchant memory without saving, so a caller can commit it in the same
    /// save as the entry that triggered it.
    public func recordLearning(payee: String, category: SpendingCategory, account: Account? = nil) throws {
        let key = MerchantKey.normalise(payee)
        guard !key.isEmpty else {
            return
        }

        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let memory: MerchantMemory

        if let exact = memories.first(where: { $0.merchantKey == key }) {
            memory = exact
        } else if let similar =
            memories
            .filter({ MerchantKey.similarity($0.merchantKey, key) >= 0.6 })
            .max(by: { $0.timesSeen < $1.timesSeen })
        {
            // A different spelling of a merchant we already know: keep one memory and
            // remember the spelling, rather than starting a second one from zero.
            memory = similar

            if !(similar.aliases ?? []).contains(where: { $0.aliasKey == key }) {
                let alias = MerchantAlias(aliasKey: key)
                alias.merchantMemory = similar
                context.insert(alias)
            }
        } else {
            let created = MerchantMemory(merchantKey: key, displayName: payee)
            context.insert(created)
            memory = created
        }

        memory.category = category
        memory.displayName = payee
        memory.account = account ?? memory.account
        memory.timesSeen += 1
        memory.lastSeenAt = Date()
        memory.record(categoryID: category.id)
    }

    public func setAutoApply(_ enabled: Bool, for payee: String) throws {
        let key = MerchantKey.normalise(payee)
        guard !key.isEmpty else {
            return
        }

        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let memory =
            memories.first { $0.merchantKey == key }
            ?? memories.first { ($0.aliases ?? []).contains { $0.aliasKey == key } }
            ?? memories.first { MerchantKey.similarity($0.merchantKey, key) >= 0.6 }

        memory?.autoApply = enabled
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    @discardableResult
    public func openContext(merchant: String, minutes: Int = 60, sourceApp: String = "") throws -> ContextWindow {
        try purgeExpiredContexts()
        let window = ContextWindow(
            merchant: merchant,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60)),
            sourceApp: sourceApp
        )
        context.insert(window)
        try context.save()
        return window
    }

    public func activeContextMerchant(at date: Date = Date()) -> String? {
        guard let windows = try? context.fetch(FetchDescriptor<ContextWindow>()) else {
            return nil
        }

        return
            windows
            .filter { $0.isActive(at: date) }
            .max { $0.expiresAt < $1.expiresAt }?
            .merchant
    }

    private func purgeExpiredContexts() throws {
        let now = Date()
        let windows = try context.fetch(FetchDescriptor<ContextWindow>())

        for window in windows where window.expiresAt < now {
            context.delete(window)
        }
    }

    private func memoryConfidence(
        _ memory: MerchantMemory,
        category: SpendingCategory,
        now: Date
    ) -> Double {
        if memory.autoApply {
            return 0.99
        }

        let counts = memory.categoryCounts
        let total = counts.values.reduce(0, +)
        let count = counts[category.id] ?? memory.timesSeen
        let share = total > 0 ? Double(count) / Double(total) : 1
        var confidence = 0.9 + 0.05 * share

        // A merchant not seen for six months is a weaker bet, but never disappears.
        if now.timeIntervalSince(memory.lastSeenAt) > 180 * 24 * 60 * 60 {
            confidence -= 0.05
        }

        return min(0.99, max(0.8, confidence))
    }

    private func isEligible(_ category: SpendingCategory, kind: CategoryKind?) -> Bool {
        guard !category.isArchived else {
            return false
        }

        guard let kind else {
            return true
        }

        return category.kind == kind
    }

    private func fetchCategories() throws -> [SpendingCategory] {
        try context.fetch(
            FetchDescriptor<SpendingCategory>(
                predicate: #Predicate<SpendingCategory> { !$0.isArchived },
                sortBy: [SortDescriptor(\SpendingCategory.sortIndex)]
            )
        )
    }

    private func historySuggestion(for key: String, kind: CategoryKind?) throws -> CategorySuggestion? {
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> { !$0.isSoftDeleted },
            sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200

        let entries = try context.fetch(descriptor)
        var counts: [UUID: (category: SpendingCategory, count: Int)] = [:]

        for entry in entries {
            guard let category = entry.category,
                isEligible(category, kind: kind),
                MerchantKey.normalise(entry.payee) == key
            else {
                continue
            }

            let current = counts[category.id]?.count ?? 0
            counts[category.id] = (category, current + 1)
        }

        guard let top = counts.values.max(by: { $0.count < $1.count }), top.count >= 2 else {
            return nil
        }

        return CategorySuggestion(
            category: top.category,
            confidence: 0.5,
            reason: "Filed here \(top.count) times before"
        )
    }

    private func bestPerCategory(_ suggestions: [CategorySuggestion]) -> [CategorySuggestion] {
        var best: [UUID: CategorySuggestion] = [:]

        for suggestion in suggestions {
            if let existing = best[suggestion.id], existing.confidence >= suggestion.confidence {
                continue
            }

            best[suggestion.id] = suggestion
        }

        return best.values.sorted { $0.confidence > $1.confidence }
    }
}
