//
//  CategoryEditorState.swift
//  SettingsFeature
//

import AppModels
import AppServices
import Foundation
import Modifiers
import Observation

/// Editable state for one spending category.
///
/// Validation mirrors `CategoryService`, so Save stays disabled until the service would
/// accept the input. The monthly default is parsed with `MoneyParser` in the display
/// currency and stored as minor units.
@MainActor
@Observable
public final class CategoryEditorState {
    public enum ValidationError: Error, Equatable {
        case invalid
    }

    public private(set) var category: SpendingCategory?
    public private(set) var groups: [CategoryGroup]
    public private(set) var categories: [SpendingCategory]

    public var displayCurrency: Currency
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var isFixed: Bool
    public var keywords: String
    public var monthlyDefaultText: String
    public var groupID: UUID?
    public var isArchived: Bool
    public var kind: CategoryKind

    public init(
        category: SpendingCategory?,
        groups: [CategoryGroup],
        categories: [SpendingCategory],
        displayCurrency: Currency = CurrencyCatalog.defaultCurrency
    ) {
        self.category = category
        self.groups = groups
        self.categories = categories
        self.displayCurrency = displayCurrency

        if let category {
            name = category.name
            symbolName = category.symbolName
            colorHex = category.colorHex
            isFixed = category.isFixed
            keywords = category.keywords
            monthlyDefaultText = Self.inputText(
                forMinorUnits: category.monthlyDefaultMinor,
                currency: displayCurrency
            )
            groupID = category.group?.id
            isArchived = category.isArchived
            kind = category.kind
        } else {
            name = ""
            symbolName = "cart"
            colorHex = ManotiPalette.categoryColours[0]
            isFixed = false
            keywords = ""
            monthlyDefaultText = ""
            groupID = groups.first?.id
            isArchived = false
            kind = .expense
        }
    }

    public var isNew: Bool {
        category == nil
    }

    public var selectedGroup: CategoryGroup? {
        guard let groupID else {
            return nil
        }

        return groups.first { $0.id == groupID }
    }

    /// The parsed monthly default in `displayCurrency`, or `nil` when blank or invalid.
    public var parsedMonthlyDefault: Money? {
        let trimmed = monthlyDefaultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isNegativeMonthlyDefault else {
            return nil
        }

        guard let parsed = MoneyParser.parse(trimmed, defaultCurrency: displayCurrency)?.money else {
            return nil
        }

        return Money(minorUnits: parsed.minorUnits, currency: displayCurrency)
    }

    public var validationMessage: String? {
        guard selectedGroup != nil else {
            return groups.isEmpty ? "No groups available. Add a group before creating a category." : "Choose a group."
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Give the category a name."
        }

        guard !isDuplicateName(trimmed) else {
            return "A category with that name already exists in this group."
        }

        if kind == .income, !(category?.budgetEnvelopes ?? []).isEmpty {
            return "This category is used by a budget envelope. Archive the envelope before making it income."
        }

        guard !isNegativeMonthlyDefault else {
            return "Enter a monthly default of zero or more."
        }

        let monthlyText = monthlyDefaultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard monthlyText.isEmpty || parsedMonthlyDefault != nil else {
            return "Enter a valid monthly default."
        }

        return nil
    }

    public var canSave: Bool {
        validationMessage == nil
    }

    @discardableResult
    public func save(using categoryService: CategoryService) throws -> SpendingCategory {
        guard validationMessage == nil, let group = selectedGroup else {
            throw ValidationError.invalid
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeywords = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let monthlyMinor = parsedMonthlyDefault?.minorUnits

        if let category {
            try categoryService.update(
                category,
                name: trimmedName,
                symbolName: symbolName,
                colorHex: colorHex,
                isFixed: isFixed,
                keywords: trimmedKeywords,
                monthlyDefaultMinor: monthlyMinor,
                group: group,
                isArchived: isArchived,
                kind: kind
            )
            name = trimmedName
            keywords = trimmedKeywords
            return category
        }

        let created = try categoryService.createCategory(
            name: trimmedName,
            symbolName: symbolName,
            colorHex: colorHex,
            isFixed: isFixed,
            keywords: trimmedKeywords,
            monthlyDefaultMinor: monthlyMinor,
            kind: kind,
            group: group
        )
        category = created
        categories.append(created)
        name = trimmedName
        keywords = trimmedKeywords
        return created
    }

    private func isDuplicateName(_ trimmedName: String) -> Bool {
        guard let groupID else {
            return false
        }

        return categories.contains { candidate in
            guard candidate.id != category?.id, candidate.group?.id == groupID else {
                return false
            }

            let candidateName = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidateName.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var isNegativeMonthlyDefault: Bool {
        let trimmed = monthlyDefaultText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("-") || trimmed.hasPrefix("−")
    }

    private static func inputText(forMinorUnits minorUnits: Int64?, currency: Currency) -> String {
        guard let minorUnits else {
            return ""
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = currency.exponent
        formatter.maximumFractionDigits = currency.exponent

        let value = Money(minorUnits: minorUnits, currency: currency).decimalValue
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}
