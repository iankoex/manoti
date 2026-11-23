//
//  BudgetEnvelopeEditorStateTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import BudgetFeature

@MainActor
@Suite("Budget envelope editor")
struct BudgetEnvelopeEditorStateTests {
    private struct Services {
        let budget: BudgetService
        let categories: CategoryService
        let context: ModelContext
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return Services(
            budget: BudgetService(context: context, calendar: calendar),
            categories: CategoryService(context: context),
            context: context
        )
    }

    private func makeDate(day: Int, month: Int = 11, year: Int = 2026, hour: Int = 12) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try #require(calendar.date(from: components))
    }

    @discardableResult
    private func makeCategory(
        _ name: String,
        isFixed: Bool = false,
        sortIndex: Int = 0,
        archived: Bool = false,
        in context: ModelContext
    ) -> SpendingCategory {
        let group = CategoryGroup(
            name: "Test group",
            symbolName: "square.grid.2x2",
            colorHex: "#FF9500"
        )
        context.insert(group)

        let category = SpendingCategory(
            name: name,
            symbolName: "circle",
            colorHex: "#FF9500",
            isFixed: isFixed,
            sortIndex: sortIndex
        )
        category.group = group
        category.isArchived = archived
        context.insert(category)
        return category
    }

    private func addEntry(
        amountMinor: Int64,
        category: SpendingCategory?,
        at occurredAt: Date,
        in context: ModelContext
    ) {
        let entry = LedgerEntry(kind: .expense, amountMinor: amountMinor, currencyCode: "KES", occurredAt: occurredAt)
        entry.category = category
        entry.status = .confirmed
        context.insert(entry)
    }

    @Test("An empty or unparseable limit cannot be saved, while zero can")
    func canSave() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: services.context)

        let state = EnvelopeEditorState(period: period, displayCurrency: .kes)
        state.reload(categories: [food])

        #expect(state.canSave == false)
        #expect(state.validationMessage == "Enter a valid limit.")

        state.limitText = "not money"
        #expect(state.canSave == false)

        state.limitText = "-10"
        #expect(state.canSave == false)
        #expect(state.validationMessage == "Enter a limit of zero or more.")

        state.limitText = "0"
        #expect(state.canSave)
        #expect(state.parsedLimit?.minorUnits == 0)
    }

    @Test("A limit parses through MoneyParser in the display currency")
    func parsing() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: services.context)

        let state = EnvelopeEditorState(period: period, displayCurrency: .kes)
        state.reload(categories: [food])
        state.limitText = "1,500.50"

        #expect(state.canSave)
        #expect(state.parsedLimit?.minorUnits == 150_050)
        #expect(state.parsedLimit?.currency == .kes)
    }

    @Test("Archived categories are excluded from the picker")
    func archivedCategoriesAreExcluded() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let active = makeCategory("Food", sortIndex: 0, in: services.context)
        let archived = makeCategory("Old food", sortIndex: 1, archived: true, in: services.context)

        let state = EnvelopeEditorState(period: period, displayCurrency: .kes)
        try state.reload(categoryService: services.categories)

        #expect(state.categories.map(\.id) == [active.id])
        #expect(state.categoryID == active.id)
        #expect(state.canSave == false)

        let oldEnvelope = Envelope(period: period, category: archived, limitMinor: 10_000)
        services.context.insert(oldEnvelope)

        let editing = EnvelopeEditorState(period: period, envelope: oldEnvelope, displayCurrency: .kes)
        try editing.reload(categoryService: services.categories)

        #expect(editing.categoryID == nil)
        #expect(editing.canSave == false)
        #expect(throws: EnvelopeEditorState.ValidationError.missingCategory) {
            try editing.save(using: services.budget)
        }
    }

    @Test("Opening an envelope in a zero-exponent currency keeps its limit")
    func displayCurrencyChange() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: services.context)
        let envelope = Envelope(
            period: period,
            category: food,
            limitMinor: 10_000,
            currencyCode: "UGX"
        )
        services.context.insert(envelope)

        let state = EnvelopeEditorState(period: period, envelope: envelope)
        #expect(state.limitText == "100")

        let ugx = CurrencyCatalog.currency(for: "UGX")
        state.setDisplayCurrency(ugx)
        #expect(state.limitText == "10000")
        #expect(state.parsedLimit?.minorUnits == 10_000)
        #expect(state.parsedLimit?.currency == ugx)
    }

    @Test("Saving upserts the envelope with its limit, rollover and trimmed note")
    func save() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: services.context)

        let state = EnvelopeEditorState(period: period, displayCurrency: .kes)
        state.reload(categories: [food])
        state.limitText = "2,000"
        state.rolloverEnabled = true
        state.note = "  Market runs  "

        let envelope = try state.save(using: services.budget)

        #expect(envelope.limitMinor == 200_000)
        #expect(envelope.rolloverEnabled)
        #expect(envelope.note == "Market runs")
        #expect(envelope.category?.id == food.id)
        #expect(envelope.period?.id == period.id)
        #expect(try services.budget.envelopes(for: period).count == 1)

        let updated = EnvelopeEditorState(period: period, envelope: envelope, displayCurrency: .kes)
        updated.reload(categories: [food])
        updated.limitText = "1,750"
        updated.rolloverEnabled = false
        try updated.save(using: services.budget)

        #expect(try services.budget.envelopes(for: period).count == 1)
        #expect(envelope.limitMinor == 175_000)
        #expect(envelope.rolloverEnabled == false)
    }

    @Test("The previous period's actual spending suggests the next limit")
    func suggestionFromLastPeriod() throws {
        let services = try makeServices()
        let food = makeCategory("Food", in: services.context)

        let october = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 15, month: 10), calendar: calendar)
        addEntry(amountMinor: 45_000, category: food, at: try makeDate(day: 10, month: 10), in: services.context)

        let november = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let state = EnvelopeEditorState(period: november, displayCurrency: .kes)
        state.reload(categories: [food])

        try state.refreshSuggestion(using: services.budget)

        #expect(try services.budget.previousPeriod(for: november)?.id == october.id)
        #expect(state.suggestedLimit?.minorUnits == 45_000)

        state.applySuggestion()
        #expect(state.limitText == "450")
    }

    @Test("Only expense categories are offered for envelopes")
    func expenseOnly() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let food = makeCategory("Food", in: services.context)
        let salary = makeCategory("Salary", sortIndex: 1, in: services.context)
        salary.kind = .income

        let state = EnvelopeEditorState(period: period, displayCurrency: .kes)
        state.reload(categories: [food, salary])

        #expect(state.categories.map(\.id) == [food.id])
    }

    @Test("BudgetService rejects an income category")
    func rejectsIncomeCategory() throws {
        let services = try makeServices()
        let period = try services.budget.currentPeriod(
            kind: .month, containing: try makeDate(day: 5), calendar: calendar)
        let salary = makeCategory("Salary", in: services.context)
        salary.kind = .income

        #expect(throws: BudgetError.incomeCategory) {
            try services.budget.setEnvelope(
                category: salary,
                limitMinor: 100_000,
                rolloverEnabled: false,
                in: period
            )
        }
    }
}
