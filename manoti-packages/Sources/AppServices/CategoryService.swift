//
//  CategoryService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum CategoryError: Error, Equatable {
    case emptyName
    case duplicateName
    case kindInUse
}

extension CategoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .emptyName:
                return "Give the category a name."
            case .duplicateName:
                return "That name is already used in this group."
            case .kindInUse:
                return "This category is used by a budget envelope. Archive the envelope before making it income."
        }
    }
}

@Observable
public final class CategoryService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Non-archived groups in sort order.
    ///
    /// Prefer `fetchAllGroups` when archived rows are needed.
    public func fetchGroups() throws -> [CategoryGroup] {
        try context.fetch(
            FetchDescriptor<CategoryGroup>(
                predicate: #Predicate<CategoryGroup> { !$0.isArchived },
                sortBy: [SortDescriptor(\CategoryGroup.sortIndex)]
            )
        )
    }

    /// Every group, including archived ones.
    ///
    /// Callers use the group's own sorted accessors.
    public func fetchAllGroups() throws -> [CategoryGroup] {
        try context.fetch(
            FetchDescriptor<CategoryGroup>(
                sortBy: [SortDescriptor(\CategoryGroup.sortIndex), SortDescriptor(\CategoryGroup.name)]
            )
        )
    }

    /// Non-archived categories, flattened in group order and then category order.
    public func fetchCategories() throws -> [SpendingCategory] {
        try fetchGroups().flatMap(\.visibleCategories)
    }

    /// Non-archived categories of one kind, in the same order as `fetchCategories()`.
    public func fetchCategories(kind: CategoryKind) throws -> [SpendingCategory] {
        try fetchCategories().filter { $0.kind == kind }
    }

    @discardableResult
    public func createCategory(
        name: String,
        symbolName: String,
        colorHex: String,
        isFixed: Bool = false,
        keywords: String = "",
        monthlyDefaultMinor: Int64? = nil,
        kind: CategoryKind = .expense,
        group: CategoryGroup? = nil
    ) throws -> SpendingCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CategoryError.emptyName
        }

        let siblings = try siblings(in: group)
        try ensureUniqueName(trimmed, among: siblings, excluding: nil)

        let nextIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1
        let category = SpendingCategory(
            name: trimmed,
            symbolName: symbolName,
            colorHex: HexColor.normalised(colorHex) ?? colorHex,
            isFixed: isFixed,
            keywords: keywords.trimmingCharacters(in: .whitespacesAndNewlines),
            sortIndex: nextIndex,
            kind: kind
        )
        category.monthlyDefaultMinor = monthlyDefaultMinor
        category.group = group
        context.insert(category)

        try context.save()
        ManotiNotifications.postDataChanged()
        return category
    }

    public func update(
        _ category: SpendingCategory,
        name: String,
        symbolName: String,
        colorHex: String,
        isFixed: Bool,
        keywords: String,
        monthlyDefaultMinor: Int64?,
        group: CategoryGroup?,
        isArchived: Bool,
        kind: CategoryKind? = nil
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CategoryError.emptyName
        }

        if let kind, kind == .income, !(category.budgetEnvelopes ?? []).isEmpty {
            throw CategoryError.kindInUse
        }

        let siblings = try siblings(in: group)
        try ensureUniqueName(trimmed, among: siblings, excluding: category)

        if category.group?.id != group?.id {
            let targetSiblings = siblings.filter { $0.id != category.id }
            category.sortIndex = (targetSiblings.map(\.sortIndex).max() ?? -1) + 1
        }

        category.name = trimmed
        category.symbolName = symbolName
        category.colorHex = HexColor.normalised(colorHex) ?? category.colorHex
        category.isFixed = isFixed
        category.keywords = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        category.monthlyDefaultMinor = monthlyDefaultMinor
        category.group = group
        category.isArchived = isArchived
        if let kind {
            category.kind = kind
        }

        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func setArchived(_ category: SpendingCategory, _ archived: Bool) throws {
        category.isArchived = archived
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// Reorders siblings by rewriting their `sortIndex`, clamping at the ends.
    public func moveCategory(_ category: SpendingCategory, by offset: Int, within group: CategoryGroup) throws {
        var siblings = sorted(group.categories ?? [])
        guard let index = siblings.firstIndex(where: { $0.id == category.id }) else {
            return
        }

        let target = min(max(index + offset, 0), siblings.count - 1)
        if target != index {
            let moved = siblings.remove(at: index)
            siblings.insert(moved, at: target)
        }

        for (position, sibling) in siblings.enumerated() {
            sibling.sortIndex = position
        }

        try context.save()
        ManotiNotifications.postDataChanged()
    }

    private func siblings(in group: CategoryGroup?) throws -> [SpendingCategory] {
        guard let group else {
            return try context.fetch(FetchDescriptor<SpendingCategory>())
                .filter { $0.group == nil }
        }

        return group.categories ?? []
    }

    private func ensureUniqueName(
        _ name: String,
        among siblings: [SpendingCategory],
        excluding category: SpendingCategory?
    ) throws {
        let clash = siblings.contains { sibling in
            guard sibling.id != category?.id else {
                return false
            }

            let siblingName = sibling.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return siblingName.caseInsensitiveCompare(name) == .orderedSame
        }

        guard !clash else {
            throw CategoryError.duplicateName
        }
    }

    private func sorted(_ categories: [SpendingCategory]) -> [SpendingCategory] {
        categories.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
