//
//  CategoriserServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("CategoriserService")
struct CategoriserServiceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return context
    }

    private func date(day: Int = 18, hour: Int, minute: Int = 0) throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute

        return try #require(Calendar.current.date(from: components))
    }

    private func category(_ name: String, in context: ModelContext) throws -> SpendingCategory {
        let all = try context.fetch(FetchDescriptor<SpendingCategory>())
        return try #require(all.first { $0.name == name })
    }

    @Test("The weekday lunch rule fires inside its window and amount band")
    func lunchRule() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let lunch = try category("Lunch", in: context)

        let suggestions = try categoriser.suggest(
            payee: "Java House",
            amountMinor: 25_000,
            date: try date(hour: 12, minute: 30)
        )

        #expect(suggestions.contains { $0.category.id == lunch.id && $0.reason == "Lunch" })
    }

    @Test("The morning window is start-inclusive and end-exclusive")
    func windowBoundaries() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let transport = try category("Bus/Matatu", in: context)

        let atStart = try categoriser.suggest(
            payee: "Stage",
            amountMinor: 6_000,
            date: try date(hour: 7, minute: 0)
        )
        #expect(atStart.contains { $0.category.id == transport.id && $0.reason == "Morning commute" })

        let atEnd = try categoriser.suggest(
            payee: "Stage",
            amountMinor: 6_000,
            date: try date(hour: 9, minute: 0)
        )
        #expect(!atEnd.contains { $0.reason == "Morning commute" })
    }

    @Test("Amount bands are inclusive")
    func amountBands() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        _ = try category("Lunch", in: context)

        let atMinimum = try categoriser.suggest(
            payee: "Cafe",
            amountMinor: 15_000,
            date: try date(hour: 13)
        )
        #expect(atMinimum.contains { $0.reason == "Lunch" })

        let aboveMaximum = try categoriser.suggest(
            payee: "Cafe",
            amountMinor: 35_001,
            date: try date(hour: 13)
        )
        #expect(!aboveMaximum.contains { $0.reason == "Lunch" })
    }

    @Test("Merchant memory outranks a smart rule")
    func memoryBeatsRule() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let shopping = try category("Household", in: context)

        try categoriser.learn(payee: "Shell Bellevue", category: shopping)

        let suggestions = try categoriser.suggest(
            payee: "Shell Bellevue",
            amountMinor: 25_000,
            date: try date(hour: 12, minute: 30)
        )

        #expect(suggestions.first?.category.id == shopping.id)
        #expect(suggestions.first?.confidence ?? 0 >= 0.9)
    }

    @Test("Only a trusted memory is auto-applicable")
    func trustedMemory() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let shopping = try category("Household", in: context)

        try categoriser.learn(payee: "Shell Bellevue", category: shopping)
        let untrusted = try categoriser.suggest(payee: "Shell Bellevue", amountMinor: 25_000)
        #expect(untrusted.first?.isAutoApplicable == false)

        try categoriser.setAutoApply(true, for: "Shell Bellevue")
        let trusted = try categoriser.suggest(payee: "Shell Bellevue", amountMinor: 25_000)
        #expect(trusted.first?.isAutoApplicable == true)
    }

    @Test("An archived category is never suggested")
    func archivedCategory() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let shopping = try category("Household", in: context)

        try categoriser.learn(payee: "Shell Bellevue", category: shopping)
        shopping.isArchived = true
        try context.save()

        let suggestions = try categoriser.suggest(
            payee: "Shell Bellevue",
            amountMinor: 25_000,
            kind: .expense
        )
        #expect(!suggestions.contains { $0.category.id == shopping.id })
    }

    @Test("A category of the other kind is never suggested")
    func wrongKind() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let salary = try category("Salary", in: context)

        try categoriser.learn(payee: "Employer", category: salary)

        let expenses = try categoriser.suggest(
            payee: "Employer",
            amountMinor: 25_000,
            kind: .expense
        )
        #expect(!expenses.contains { $0.category.id == salary.id })
    }

    @Test("Learning the same merchant twice increments the count")
    func learning() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let food = try category("Takeout", in: context)

        try categoriser.learn(payee: "Glovo", category: food)
        try categoriser.learn(payee: "Glovo", category: food)

        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let memory = try #require(memories.first { $0.merchantKey == "glovo" })

        #expect(memory.timesSeen == 2)
        #expect(memory.category?.id == food.id)
    }

    @Test("An active ride context suggests ride-hailing and expires")
    func contextWindow() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let rides = try category("Ride-hailing", in: context)

        try categoriser.openContext(merchant: "Uber", minutes: 60)

        let active = try categoriser.suggest(
            payee: "Uber Trip",
            amountMinor: 30_000,
            date: Date()
        )
        #expect(active.contains { $0.category.id == rides.id })

        for window in try context.fetch(FetchDescriptor<ContextWindow>()) {
            context.delete(window)
        }

        let expired = ContextWindow(
            merchant: "Uber",
            startedAt: Date().addingTimeInterval(-7_200),
            expiresAt: Date().addingTimeInterval(-3_600)
        )
        context.insert(expired)
        try context.save()

        let noContext = try categoriser.suggest(
            payee: "Uber Trip",
            amountMinor: 30_000,
            date: Date()
        )
        #expect(!noContext.contains { $0.reason.contains("Uber ride") })
    }

    @Test("The lowest-priority matching smart rule wins")
    func rulePriority() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let lunch = try category("Lunch", in: context)
        let transport = try category("Bus/Matatu", in: context)

        let first = SmartRule(
            name: "First",
            priority: 0,
            conditions: SmartRuleConditions(amountMinMinor: 1),
            confidenceBoost: 0
        )
        first.targetCategory = lunch
        context.insert(first)

        let second = SmartRule(
            name: "Second",
            priority: 1,
            conditions: SmartRuleConditions(amountMinMinor: 1),
            confidenceBoost: 0.5
        )
        second.targetCategory = transport
        context.insert(second)
        try context.save()

        // A fixed 10:00 avoids the seeded meal and commute rules, which are time-of-day based.
        let at = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        let suggestions = try categoriser.suggest(payee: "Shop", amountMinor: 10_000, date: at)
        #expect(suggestions.contains { $0.category.id == lunch.id && $0.reason == "First" })
        #expect(!suggestions.contains { $0.category.id == transport.id })
    }

    @Test("A fragment only matches a whole word")
    func wholeWordMatching() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)

        let suggestions = try categoriser.suggest(payee: "SMART MOBILE", amountMinor: 100_000)
        #expect(!suggestions.contains { $0.reason == "Supermarket" })
    }

    @Test("A payee-less message can still match a context rule")
    func emptyPayeeContext() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let rides = try category("Ride-hailing", in: context)

        try categoriser.openContext(merchant: "Uber", minutes: 60)

        // A fixed 10:00 avoids the seeded meal and commute rules, which are time-of-day based.
        let at = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
        let suggestions = try categoriser.suggest(
            payee: "",
            amountMinor: 30_000,
            date: at,
            contextMerchant: "Uber",
            kind: .expense
        )

        #expect(suggestions.contains { $0.category.id == rides.id })
    }

    @Test("A food-delivery context does not count as a ride")
    func contextIsExact() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)

        try categoriser.openContext(merchant: "Uber Eats", minutes: 60)

        let suggestions = try categoriser.suggest(payee: "Uber Trip", amountMinor: 30_000)
        #expect(!suggestions.contains { $0.reason == "Uber ride" })
    }

    @Test("A near-miss payee suggests the remembered category")
    func nearMissSuggestion() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let fuel = try category("Fuel", in: context)

        try categoriser.learn(payee: "Shell Bellevue", category: fuel)

        let suggestions = try categoriser.suggest(
            payee: "Shell Bellevue Nairobi",
            amountMinor: 1_000
        )

        #expect(suggestions.contains { $0.category.id == fuel.id && $0.reason == "Similar merchant: Shell Bellevue" })
        #expect(suggestions.first { $0.reason == "Similar merchant: Shell Bellevue" }?.confidence == 0.8)
    }

    @Test("A near-miss confirmation keeps one memory and records the spelling")
    func aliasNearMiss() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let fuel = try category("Fuel", in: context)

        try categoriser.learn(payee: "Shell Bellevue", category: fuel)
        try categoriser.learn(payee: "Shell Bellevue Nairobi", category: fuel)

        let memories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let memory = try #require(memories.first)

        #expect(memories.count == 1)
        #expect(memory.timesSeen == 2)
        #expect(memory.aliases?.contains { $0.aliasKey == "shell bellevue nairobi" } == true)
    }

    @Test("A merchant filed under two categories keeps the other one available")
    func splitMerchant() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let takeout = try category("Takeout", in: context)
        let household = try category("Household", in: context)

        try categoriser.learn(payee: "Glovo", category: takeout)
        try categoriser.learn(payee: "Glovo", category: takeout)
        try categoriser.learn(payee: "Glovo", category: household)

        let suggestions = try categoriser.suggest(payee: "Glovo", amountMinor: 1_000)

        #expect(suggestions.contains { $0.category.id == takeout.id })
        #expect(suggestions.contains { $0.category.id == household.id })
        #expect(suggestions.first?.category.id == household.id)
    }

    @Test("A merchant not seen for six months scores lower than a fresh one")
    func recency() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let fuel = try category("Fuel", in: context)

        try categoriser.learn(payee: "Shell Bellevue", category: fuel)
        let fresh = try #require(try categoriser.suggest(payee: "Shell Bellevue", amountMinor: 1_000).first)

        let memory = try #require(try context.fetch(FetchDescriptor<MerchantMemory>()).first)
        memory.lastSeenAt = Date().addingTimeInterval(-200 * 24 * 60 * 60)
        try context.save()

        let stale = try #require(try categoriser.suggest(payee: "Shell Bellevue", amountMinor: 1_000).first)
        #expect(stale.confidence < fresh.confidence)
        #expect(stale.confidence >= 0.8)
    }

    @Test("Payee keywords fall back when no rule matches")
    func keywords() throws {
        let context = try makeContext()
        let categoriser = CategoriserService(context: context)
        let groceries = try category("Groceries", in: context)

        let suggestions = try categoriser.suggest(
            payee: "Quickmart",
            amountMinor: 10_000,
            date: try date(hour: 15)
        )

        #expect(suggestions.contains { $0.category.id == groceries.id })
    }
}
