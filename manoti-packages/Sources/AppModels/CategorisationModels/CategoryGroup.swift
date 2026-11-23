//
//  CategoryGroup.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class CategoryGroup {
    public var id: UUID = UUID()
    public var name: String = ""
    public var symbolName: String = "square.grid.2x2"
    public var colorHex: String = "#8E8E93"
    public var sortIndex: Int = 0
    public var isArchived: Bool = false
    /// Stable identity used by seeding so a renamed group is never duplicated.
    public var seedKey: String = ""

    @Relationship(deleteRule: .nullify, inverse: \SpendingCategory.group)
    public var categories: [SpendingCategory]?

    public init(name: String, symbolName: String, colorHex: String, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }

    /// Every category in the group, including archived ones, ordered by `sortIndex`.
    public var sortedCategories: [SpendingCategory] {
        (categories ?? [])
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    public var visibleCategories: [SpendingCategory] {
        sortedCategories.filter { !$0.isArchived }
    }
}
