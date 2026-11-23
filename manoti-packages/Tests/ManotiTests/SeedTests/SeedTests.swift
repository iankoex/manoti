//
//  SeedTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppPackageExtensions
@testable import AppServices

@MainActor
@Suite("Seeding")
struct SeedTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    @Test("Seeding creates the full taxonomy and one settings row")
    func seedsOnce() throws {
        let context = try makeContext()
        let service = SeedService(context: context)

        try service.seedIfNeeded()

        #expect(try context.fetchCount(FetchDescriptor<CategoryGroup>()) == 12)
        #expect(try context.fetchCount(FetchDescriptor<SpendingCategory>()) == 42)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test("Seeded income categories are marked as income")
    func seededIncomeKind() throws {
        let context = try makeContext()
        try SeedService(context: context).seedIfNeeded()

        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        let salary = try #require(categories.first { $0.name == "Salary" })
        let lunch = try #require(categories.first { $0.name == "Lunch" })

        #expect(salary.kind == .income)
        #expect(lunch.kind == .expense)
        #expect(try context.fetch(FetchDescriptor<AppSettings>()).first?.categoryKindsMigrated == true)
    }

    @Test("The income migration is one-time and keeps a later manual change")
    func incomeMigrationIsOneTime() throws {
        let context = try makeContext()
        let service = SeedService(context: context)
        try service.seedIfNeeded()

        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        let salary = try #require(categories.first { $0.name == "Salary" })
        salary.kind = .expense
        try context.save()

        try service.seedIfNeeded()

        #expect(salary.kind == .expense)
    }

    @Test("The income repair fixes categories restored from an old backup once")
    func incomeRepairIsOneTime() throws {
        let context = try makeContext()
        let service = SeedService(context: context)
        try service.seedIfNeeded()

        let settings = try #require(try context.fetch(FetchDescriptor<AppSettings>()).first)
        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        let salary = try #require(categories.first { $0.name == "Salary" })

        // Simulate an old backup restore: income categories became expenses and the
        // one-time migration flag is already set.
        salary.kind = .expense
        settings.categoryKindsRepaired = false
        try context.save()

        try service.seedIfNeeded()

        #expect(salary.kind == .income)
        #expect(settings.categoryKindsRepaired)

        // A later deliberate change is not overwritten.
        salary.kind = .expense
        try context.save()
        try service.seedIfNeeded()

        #expect(salary.kind == .expense)
    }

    @Test("Seeded display names are provider-neutral")
    func brandNeutralNames() throws {
        let context = try makeContext()
        try SeedService(context: context).seedIfNeeded()

        let ruleSets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let names = Set(ruleSets.map(\.name))
        #expect(names.contains("Mobile money"))
        #expect(names.contains("Bank"))
        #expect(!names.contains { $0.contains("M-Pesa") || $0.contains("I&M") })

        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        #expect(!categories.contains { $0.name == "M-Pesa fees" })
        #expect(categories.contains { $0.name == "Mobile money fees" })
    }

    @Test("Seeding twice changes nothing")
    func idempotent() throws {
        let context = try makeContext()
        let service = SeedService(context: context)

        try service.seedIfNeeded()
        try service.seedIfNeeded()

        #expect(try context.fetchCount(FetchDescriptor<CategoryGroup>()) == 12)
        #expect(try context.fetchCount(FetchDescriptor<SpendingCategory>()) == 42)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test("Every seed colour is valid and every name is unique")
    func seedQuality() throws {
        let context = try makeContext()
        try SeedService(context: context).seedIfNeeded()

        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())

        for group in groups {
            #expect(HexColor.normalised(group.colorHex) != nil, "\(group.name)")
            let names = (group.categories ?? []).map(\.name)
            #expect(Set(names).count == names.count, "duplicate category in \(group.name)")
        }

        for category in categories {
            #expect(HexColor.normalised(category.colorHex) != nil, "\(category.name)")
            #expect(!category.name.isEmpty)
        }
    }

    @Test("Fixed-cost categories are the ones the spec marks")
    func fixedCosts() throws {
        let context = try makeContext()
        try SeedService(context: context).seedIfNeeded()

        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        let fixed = Set(categories.filter(\.isFixed).map(\.name))

        #expect(fixed == ["Rent", "Service charge", "Insurance", "Fees"])
    }

    @Test("Legacy rows with an empty seed key are adopted, not duplicated")
    func legacyEmptySeedKeys() throws {
        let context = try makeContext()
        let service = SeedService(context: context)
        try service.seedIfNeeded()

        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let food = try #require(groups.first { $0.name == "Food" })
        food.seedKey = ""

        let ruleSets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let mpesa = try #require(ruleSets.first { $0.seedKey == "mpesa" })
        mpesa.seedKey = ""
        mpesa.name = "Mobile money"

        let smartRules = try context.fetch(FetchDescriptor<SmartRule>())
        let lunch = try #require(smartRules.first { $0.seedKey == "lunch" })
        lunch.seedKey = ""
        try context.save()

        try service.seedIfNeeded()

        #expect(try context.fetchCount(FetchDescriptor<CategoryGroup>()) == 12)
        #expect(try context.fetchCount(FetchDescriptor<ParseRuleSet>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<SmartRule>()) == 7)
        #expect(food.seedKey == "food")
        #expect(mpesa.seedKey == "mpesa")
        #expect(lunch.seedKey == "lunch")
    }

    @Test("Seeding respects a user-renamed group")
    func preservesEdits() throws {
        let context = try makeContext()
        let service = SeedService(context: context)
        try service.seedIfNeeded()

        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let food = try #require(groups.first { $0.name == "Food" })
        food.name = "Kula"

        try service.seedIfNeeded()

        #expect(try context.fetchCount(FetchDescriptor<CategoryGroup>()) == 12)
        #expect(groups.contains { $0.name == "Kula" })
    }
}
