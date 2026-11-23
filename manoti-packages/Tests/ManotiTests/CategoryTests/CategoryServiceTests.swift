//
//  CategoryServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("CategoryService")
struct CategoryServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return context
    }

    private func makeGroup(_ name: String, in context: ModelContext) -> CategoryGroup {
        let group = CategoryGroup(name: name, symbolName: "square.grid.2x2", colorHex: "#8E8E93")
        context.insert(group)
        return group
    }

    @Test("A new category is an expense by default")
    func defaultKind() throws {
        _ = try makeContext()
        let category = SpendingCategory(name: "Test", symbolName: "circle", colorHex: "#FF9500")

        #expect(category.kind == .expense)
        #expect(!category.isIncome)
    }

    @Test("Kind is created, updated and filtered")
    func categoryKind() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let group = makeGroup("Kind test", in: context)

        let salary = try service.createCategory(
            name: "Test salary",
            symbolName: "banknote",
            colorHex: "#34C759",
            kind: .income,
            group: group
        )
        let lunch = try service.createCategory(
            name: "Test lunch",
            symbolName: "fork.knife",
            colorHex: "#FF9F0A",
            group: group
        )

        #expect(salary.kind == .income)
        #expect(lunch.kind == .expense)

        let income = try service.fetchCategories(kind: .income)
        let expense = try service.fetchCategories(kind: .expense)
        #expect(income.contains { $0.id == salary.id })
        #expect(!income.contains { $0.id == lunch.id })
        #expect(income.allSatisfy { $0.kind == .income })
        #expect(expense.contains { $0.id == lunch.id })
        #expect(!expense.contains { $0.id == salary.id })
        #expect(expense.allSatisfy { $0.kind == .expense })

        try service.update(
            lunch,
            name: lunch.name,
            symbolName: lunch.symbolName,
            colorHex: lunch.colorHex,
            isFixed: false,
            keywords: "",
            monthlyDefaultMinor: nil,
            group: group,
            isArchived: false,
            kind: .income
        )
        #expect(lunch.kind == .income)
    }

    @Test("Categories follow group order, then category order")
    func ordering() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)

        let names = try service.fetchCategories().map(\.name)

        #expect(names.count == 42)
        #expect(
            Array(names.prefix(12)) == [
                "Bus/Matatu", "Taxi", "Ride-hailing", "Fuel", "Parking",
                "Breakfast", "Lunch", "Dinner", "Takeout", "Groceries", "Coffee",
                "Household",
            ])
        #expect(names.last == "Uncategorised")
    }

    @Test("Archived categories and groups are excluded")
    func excludesArchived() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let groups = try service.fetchGroups()
        let food = try #require(groups.first { $0.name == "Food" })

        food.isArchived = true
        try context.save()

        let names = try service.fetchCategories().map(\.name)
        #expect(!names.contains("Lunch"))
        #expect(try service.fetchGroups().count == 11)
        #expect(try service.fetchCategories().count == 36)
    }

    @Test("Creating and updating a category round-trips every field")
    func createAndUpdate() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let food = try #require(try service.fetchAllGroups().first { $0.name == "Food" })

        let created = try service.createCategory(
            name: "  Snacks  ",
            symbolName: "carrot",
            colorHex: "#FF0000",
            isFixed: true,
            keywords: "  chips, crisps ",
            monthlyDefaultMinor: 150_000,
            group: food
        )

        #expect(created.name == "Snacks")
        #expect(created.symbolName == "carrot")
        #expect(created.colorHex == "FF0000")
        #expect(created.isFixed)
        #expect(created.keywords == "chips, crisps")
        #expect(created.monthlyDefaultMinor == 150_000)
        #expect(created.group?.id == food.id)
        #expect(created.sortIndex == 6)
        #expect(try service.fetchCategories().contains { $0.id == created.id })

        try service.update(
            created,
            name: "Snacks & treats",
            symbolName: "birthday.cake",
            colorHex: "#00FF00",
            isFixed: false,
            keywords: "  chips  ",
            monthlyDefaultMinor: nil,
            group: food,
            isArchived: false
        )

        #expect(created.name == "Snacks & treats")
        #expect(created.symbolName == "birthday.cake")
        #expect(created.colorHex == "00FF00")
        #expect(created.isFixed == false)
        #expect(created.keywords == "chips")
        #expect(created.monthlyDefaultMinor == nil)
        #expect(created.group?.id == food.id)
    }

    @Test("Duplicate names are rejected within a group but allowed across groups")
    func duplicateNames() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let groups = try service.fetchAllGroups()
        let food = try #require(groups.first { $0.name == "Food" })
        let transport = try #require(groups.first { $0.name == "Transport" })

        #expect(throws: CategoryError.duplicateName) {
            try service.createCategory(
                name: " lunch ",
                symbolName: "circle",
                colorHex: "#8E8E93",
                group: food
            )
        }

        let allowed = try service.createCategory(
            name: "Lunch",
            symbolName: "circle",
            colorHex: "#8E8E93",
            group: transport
        )

        #expect(allowed.group?.id == transport.id)
        #expect(try service.fetchCategories().filter { $0.name == "Lunch" }.count == 2)
    }

    @Test("Empty names are rejected")
    func emptyName() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let food = try #require(try service.fetchAllGroups().first { $0.name == "Food" })

        #expect(throws: CategoryError.emptyName) {
            try service.createCategory(
                name: "   ",
                symbolName: "circle",
                colorHex: "#8E8E93",
                group: food
            )
        }
    }

    @Test("Archiving hides a category from active fetches and unarchiving restores it")
    func archiveAndUnarchive() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let lunch = try #require(try service.fetchCategories().first { $0.name == "Lunch" })

        try service.setArchived(lunch, true)

        #expect(lunch.isArchived)
        #expect(try service.fetchCategories().contains { $0.id == lunch.id } == false)
        #expect(try service.fetchAllGroups().flatMap(\.sortedCategories).contains { $0.id == lunch.id })

        try service.setArchived(lunch, false)

        #expect(lunch.isArchived == false)
        #expect(try service.fetchCategories().contains { $0.id == lunch.id })
    }

    @Test("Moving by an offset reorders siblings and clamps at both ends")
    func reorderClamps() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let group = makeGroup("Reorder", in: context)

        let first = try service.createCategory(
            name: "A", symbolName: "circle", colorHex: "#8E8E93", group: group)
        let second = try service.createCategory(
            name: "B", symbolName: "circle", colorHex: "#8E8E93", group: group)
        let third = try service.createCategory(
            name: "C", symbolName: "circle", colorHex: "#8E8E93", group: group)

        #expect(group.sortedCategories.map(\.name) == ["A", "B", "C"])

        try service.moveCategory(first, by: 1, within: group)
        #expect(group.sortedCategories.map(\.name) == ["B", "A", "C"])
        #expect(group.sortedCategories.map(\.sortIndex) == [0, 1, 2])

        try service.moveCategory(first, by: -10, within: group)
        #expect(group.sortedCategories.map(\.name) == ["A", "B", "C"])
        #expect(group.sortedCategories.map(\.sortIndex) == [0, 1, 2])

        try service.moveCategory(third, by: 50, within: group)
        #expect(group.sortedCategories.map(\.name) == ["A", "B", "C"])

        try service.moveCategory(second, by: -1, within: group)
        #expect(group.sortedCategories.map(\.name) == ["B", "A", "C"])
    }

    @Test("fetchAllGroups includes archived groups and sorts groups and categories")
    func fetchAllGroupsIncludesArchived() throws {
        let context = try makeContext()
        let service = CategoryService(context: context)
        let food = try #require(try service.fetchAllGroups().first { $0.name == "Food" })

        food.isArchived = true
        try context.save()

        #expect(try service.fetchGroups().count == 11)

        let all = try service.fetchAllGroups()
        #expect(all.count == 12)
        #expect(all.map(\.sortIndex) == all.map(\.sortIndex).sorted())
        #expect(all.contains { $0.id == food.id && $0.isArchived })

        let archivedFood = try #require(all.first { $0.id == food.id })
        #expect(
            archivedFood.sortedCategories.map(\.sortIndex) == archivedFood.sortedCategories.map(\.sortIndex).sorted())
        #expect(archivedFood.sortedCategories.first?.name == "Breakfast")
    }
}
