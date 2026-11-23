//
//  CategoryEditorStateTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import SettingsFeature

@MainActor
@Suite("Category editor")
struct CategoryEditorStateTests {
    private struct Services {
        let categories: CategoryService
        let context: ModelContext
    }

    private var currency: Currency {
        Currency(code: "KES", exponent: 2)
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return Services(categories: CategoryService(context: context), context: context)
    }

    private func makeState(
        category: SpendingCategory? = nil,
        services: Services
    ) throws -> CategoryEditorState {
        let groups = try services.categories.fetchAllGroups()
        let categories = groups.flatMap(\.sortedCategories)
        return CategoryEditorState(
            category: category,
            groups: groups,
            categories: categories,
            displayCurrency: currency
        )
    }

    private func group(named name: String, in services: Services) throws -> CategoryGroup {
        try #require(try services.categories.fetchAllGroups().first { $0.name == name })
    }

    @Test("Editing prefills every field and parses the stored monthly default")
    func prefill() throws {
        let services = try makeServices()
        let lunch = try #require(try services.categories.fetchCategories().first { $0.name == "Lunch" })
        lunch.monthlyDefaultMinor = 123_450
        lunch.keywords = "midday, cafe"

        let state = try makeState(category: lunch, services: services)

        #expect(state.isNew == false)
        #expect(state.name == "Lunch")
        #expect(state.symbolName == lunch.symbolName)
        #expect(state.colorHex == lunch.colorHex)
        #expect(state.groupID == lunch.group?.id)
        #expect(state.keywords == "midday, cafe")
        #expect(state.monthlyDefaultText == "1234.50")
        #expect(state.parsedMonthlyDefault?.minorUnits == 123_450)
        #expect(state.parsedMonthlyDefault?.currency == currency)
        #expect(state.canSave)
    }

    @Test("Kind is editable and persisted")
    func kindPersists() throws {
        let services = try makeServices()
        let lunch = try #require(try services.categories.fetchCategories().first { $0.name == "Lunch" })
        let state = try makeState(category: lunch, services: services)

        #expect(state.kind == .expense)
        state.kind = .income
        #expect(state.canSave)

        try state.save(using: services.categories)
        #expect(lunch.kind == .income)
    }

    @Test("A category used by a budget envelope cannot become income")
    func envelopeBlocksIncome() throws {
        let services = try makeServices()
        let lunch = try #require(try services.categories.fetchCategories().first { $0.name == "Lunch" })
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let period = BudgetPeriod(
            kind: .month,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 86_400)
        )
        services.context.insert(period)
        services.context.insert(
            Envelope(period: period, category: lunch, limitMinor: 100_000, currencyCode: "KES")
        )
        try services.context.save()

        let state = try makeState(category: lunch, services: services)
        state.kind = .income

        #expect(!state.canSave)
        #expect(state.validationMessage?.contains("budget envelope") == true)
    }

    @Test("Saving trims the name and keywords and stores the parsed monthly default")
    func saveCreatesTrimmedCategory() throws {
        let services = try makeServices()
        let transport = try group(named: "Transport", in: services)
        let before = try services.categories.fetchAllGroups().flatMap(\.sortedCategories).count

        let state = try makeState(services: services)
        state.groupID = transport.id
        state.name = "  Snacks  "
        state.keywords = "  chips, crisps  "
        state.monthlyDefaultText = "1,200.50"
        state.isFixed = true

        let created = try state.save(using: services.categories)

        #expect(created.id == state.category?.id)
        #expect(state.isNew == false)
        #expect(created.name == "Snacks")
        #expect(created.keywords == "chips, crisps")
        #expect(created.monthlyDefaultMinor == 120_050)
        #expect(created.isFixed)
        #expect(created.group?.id == transport.id)
        #expect(try services.categories.fetchAllGroups().flatMap(\.sortedCategories).count == before + 1)
    }

    @Test("A duplicate name is blocked within a group but allowed in another group")
    func duplicateNameScope() throws {
        let services = try makeServices()
        let food = try group(named: "Food", in: services)
        let transport = try group(named: "Transport", in: services)

        let state = try makeState(services: services)
        state.groupID = food.id
        state.name = " lunch "

        #expect(state.canSave == false)
        #expect(state.validationMessage == "A category with that name already exists in this group.")

        state.groupID = transport.id
        #expect(state.canSave)
        #expect(state.validationMessage == nil)
    }

    @Test("An empty name cannot be saved")
    func emptyNameBlocked() throws {
        let services = try makeServices()
        let state = try makeState(services: services)
        state.name = "   "

        #expect(state.canSave == false)
        #expect(state.validationMessage == "Give the category a name.")
    }

    @Test("An invalid monthly default blocks saving while a blank one is allowed")
    func invalidMonthlyDefaultBlocked() throws {
        let services = try makeServices()
        let state = try makeState(services: services)
        state.name = "Snacks"

        #expect(state.monthlyDefaultText.isEmpty)
        #expect(state.canSave)

        state.monthlyDefaultText = "not money"
        #expect(state.canSave == false)
        #expect(state.validationMessage == "Enter a valid monthly default.")

        state.monthlyDefaultText = "-50"
        #expect(state.canSave == false)
        #expect(state.validationMessage == "Enter a monthly default of zero or more.")

        state.monthlyDefaultText = "0"
        #expect(state.canSave)
        #expect(state.parsedMonthlyDefault?.minorUnits == 0)
    }

    @Test("Saving an existing category updates that row without creating another")
    func saveUpdatesSameRow() throws {
        let services = try makeServices()
        let lunch = try #require(try services.categories.fetchCategories().first { $0.name == "Lunch" })
        let before = try services.categories.fetchAllGroups().flatMap(\.sortedCategories).count

        let state = try makeState(category: lunch, services: services)
        state.name = "Midday meal"
        state.monthlyDefaultText = "800"

        let saved = try state.save(using: services.categories)

        #expect(saved.id == lunch.id)
        #expect(try services.categories.fetchAllGroups().flatMap(\.sortedCategories).count == before)
        #expect(try services.categories.fetchCategories().first { $0.id == lunch.id }?.name == "Midday meal")
        #expect(lunch.monthlyDefaultMinor == 80_000)
    }

    @Test("The archive flag is persisted through save")
    func archiveFlagPersists() throws {
        let services = try makeServices()
        let lunch = try #require(try services.categories.fetchCategories().first { $0.name == "Lunch" })

        let state = try makeState(category: lunch, services: services)
        state.isArchived = true

        try state.save(using: services.categories)

        #expect(lunch.isArchived)
        #expect(state.category?.isArchived == true)
        #expect(try services.categories.fetchCategories().contains { $0.id == lunch.id } == false)
        #expect(try services.categories.fetchAllGroups().flatMap(\.sortedCategories).contains { $0.id == lunch.id })
    }
}
