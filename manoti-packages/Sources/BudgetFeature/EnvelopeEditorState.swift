//
//  EnvelopeEditorState.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Foundation
import Observation

/// Editable state for one category envelope.
///
/// Validation mirrors `BudgetService.setEnvelope`, so Save stays disabled until the
/// service would accept the input. Limits use `MoneyParser` and are stored in the app's
/// display currency.
@MainActor
@Observable
public final class EnvelopeEditorState {
    public enum ValidationError: Error, Equatable {
        case missingCategory
        case archivedCategory
        case invalidLimit
    }

    public let period: BudgetPeriod
    public private(set) var envelope: Envelope?
    public private(set) var categories: [SpendingCategory] = []
    public private(set) var suggestedLimit: Money?

    public var displayCurrency: Currency
    public var categoryID: UUID?
    public var limitText: String
    public var rolloverEnabled: Bool
    public var note: String

    public init(
        period: BudgetPeriod,
        envelope: Envelope? = nil,
        displayCurrency: Currency = CurrencyCatalog.defaultCurrency
    ) {
        self.period = period
        self.envelope = envelope
        self.displayCurrency = displayCurrency

        if let envelope {
            categoryID = envelope.category?.id
            limitText = BudgetFormatting.limitText(
                for: Money(minorUnits: envelope.limitMinor, currency: displayCurrency)
            )
            rolloverEnabled = envelope.rolloverEnabled
            note = envelope.note
        } else {
            categoryID = nil
            limitText = ""
            rolloverEnabled = false
            note = ""
        }
    }

    /// Applies the real display currency after construction and reformats the existing
    /// limit. The view cannot pass the environment value into `init`, and formatting with
    /// the default (KES) would show a UGX or JPY limit at one hundredth of its value.
    public func setDisplayCurrency(_ currency: Currency) {
        displayCurrency = currency

        guard let envelope else {
            return
        }

        limitText = BudgetFormatting.limitText(
            for: Money(minorUnits: envelope.limitMinor, currency: currency)
        )
    }

    public var selectedCategory: SpendingCategory? {
        if let categoryID, let match = categories.first(where: { $0.id == categoryID }) {
            return match
        }

        guard categories.isEmpty, let category = envelope?.category, category.id == categoryID else {
            return nil
        }

        return category
    }

    /// The parsed limit in `displayCurrency`, or `nil` when the text is not an amount.
    public var parsedLimit: Money? {
        guard !isNegativeInput,
            let parsed = MoneyParser.parse(limitText, defaultCurrency: displayCurrency)?.money
        else {
            return nil
        }

        return Money(minorUnits: parsed.minorUnits, currency: displayCurrency)
    }

    public var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validationMessage: String? {
        guard let category = selectedCategory else {
            return categories.isEmpty ? "No active categories available." : "Choose a category."
        }

        guard !category.isArchived else {
            return "That category is archived."
        }

        guard !isNegativeInput else {
            return "Enter a limit of zero or more."
        }

        guard parsedLimit != nil else {
            return "Enter a valid limit."
        }

        return nil
    }

    public var canSave: Bool {
        validationMessage == nil
    }

    /// Loads the non-archived expense categories the picker may offer.
    public func reload(categoryService: CategoryService) throws {
        reload(categories: try categoryService.fetchCategories(kind: .expense))
    }

    /// Replaces the picker contents, excluding archived and income categories.
    public func reload(categories: [SpendingCategory]) {
        self.categories =
            categories
            .filter { !$0.isArchived && ($0.kind == .expense || $0.id == envelope?.category?.id) }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        if let categoryID {
            if !self.categories.contains(where: { $0.id == categoryID }) {
                // Never silently retarget an existing envelope whose category is archived.
                self.categoryID = envelope == nil ? self.categories.first?.id : nil
            }
        } else {
            self.categoryID = self.categories.first?.id
        }
    }

    /// Last period's actual spending for the selected category, when there is one.
    public func refreshSuggestion(using budgetService: BudgetService) throws {
        guard let category = selectedCategory,
            let previous = try budgetService.previousPeriod(for: period)
        else {
            suggestedLimit = nil
            return
        }

        let actual = try budgetService.actualMinor(for: category, in: previous)
        suggestedLimit = actual > 0 ? Money(minorUnits: actual, currency: displayCurrency) : nil
    }

    public func applySuggestion() {
        guard let suggestedLimit else {
            return
        }

        limitText = BudgetFormatting.limitText(for: suggestedLimit)
    }

    @discardableResult
    public func save(using budgetService: BudgetService) throws -> Envelope {
        guard let category = selectedCategory else {
            throw ValidationError.missingCategory
        }

        guard !category.isArchived else {
            throw ValidationError.archivedCategory
        }

        guard let limit = parsedLimit else {
            throw ValidationError.invalidLimit
        }

        let saved = try budgetService.setEnvelope(
            category: category,
            limitMinor: limit.minorUnits,
            rolloverEnabled: rolloverEnabled,
            note: trimmedNote,
            in: period
        )
        envelope = saved
        return saved
    }

    private var isNegativeInput: Bool {
        let trimmed = limitText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("-") || trimmed.hasPrefix("−")
    }
}
