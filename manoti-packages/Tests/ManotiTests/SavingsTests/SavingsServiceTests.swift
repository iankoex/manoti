//
//  SavingsServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import BudgetFeature

@MainActor
@Suite("Savings")
struct SavingsServiceTests {
    private struct Fixtures {
        let context: ModelContext
        let savings: SavingsService
        let accounts: AccountService
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let accounts = AccountService(context: context)
        return Fixtures(
            context: context,
            savings: SavingsService(context: context),
            accounts: accounts
        )
    }

    @Test("A sinking fund totals its contributions and can be archived")
    func fundContributions() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let fund = try fixtures.savings.createFund(
            name: "  Car service  ",
            targetMinor: 300_000,
            monthlyAccrualMinor: 25_000,
            account: account
        )

        #expect(fund.name == "Car service")
        #expect(fund.fundedMinor == 0)

        try fixtures.savings.addContribution(to: fund, amountMinor: 20_000, account: account)
        try fixtures.savings.addContribution(to: fund, amountMinor: 5_000, account: account)

        #expect(fund.fundedMinor == 25_000)
        #expect(fixtures.savings.contributions(for: fund).count == 2)

        try fixtures.savings.updateFund(
            fund,
            name: fund.name,
            targetMinor: fund.targetMinor,
            monthlyAccrualMinor: 0,
            targetDate: nil,
            currencyCode: "KES",
            category: nil,
            account: account,
            note: "",
            isArchived: true
        )

        #expect(try fixtures.savings.fetchFunds().isEmpty)
        #expect(try fixtures.savings.fetchFunds(includeArchived: true).count == 1)
    }

    @Test("A contribution needs a positive amount")
    func contributionValidation() throws {
        let fixtures = try makeFixtures()
        let fund = try fixtures.savings.createFund(name: "Repairs", targetMinor: 100_000)

        #expect(throws: SavingsError.invalidAmount) {
            try fixtures.savings.addContribution(to: fund, amountMinor: 0)
        }
    }

    @Test("A goal linked to an account derives progress from its balance")
    func goalProgress() throws {
        let fixtures = try makeFixtures()
        let account = try fixtures.accounts.create(
            name: "Savings",
            kind: .bank,
            openingBalanceMinor: 250_000
        )
        let goal = try fixtures.savings.createGoal(
            name: "Emergency fund",
            targetMinor: 1_000_000,
            account: account
        )

        #expect(goal.progressMinor == 250_000)
        #expect(goal.targetMinor == 1_000_000)
    }

    @Test("Savings targets keep their currency and reject a mismatched account")
    func savingsCurrency() throws {
        let fixtures = try makeFixtures()
        let ugx = try fixtures.accounts.create(name: "UGX wallet", kind: .mobileMoney, currencyCode: "UGX")

        #expect(throws: SavingsError.currencyMismatch(expected: "UGX", actual: "KES")) {
            try fixtures.savings.createGoal(
                name: "Trip",
                targetMinor: 100_000,
                currencyCode: "KES",
                account: ugx
            )
        }

        let fund = try fixtures.savings.createFund(name: "Repairs", targetMinor: 100_000)
        #expect(fund.currencyCode == "KES")

        try fixtures.savings.updateFund(
            fund,
            name: fund.name,
            targetMinor: fund.targetMinor,
            monthlyAccrualMinor: 0,
            targetDate: nil,
            currencyCode: "UGX",
            category: nil,
            account: nil,
            note: "",
            isArchived: false
        )
        #expect(fund.currencyCode == "UGX")
    }

    @Test("Names and archived accounts are validated")
    func validation() throws {
        let fixtures = try makeFixtures()
        let archived = try fixtures.accounts.create(name: "Old", kind: .bank)
        try fixtures.accounts.archive(archived)

        #expect(throws: SavingsError.emptyName) {
            try fixtures.savings.createFund(name: "   ", targetMinor: 100)
        }

        #expect(throws: SavingsError.archivedAccount) {
            try fixtures.savings.createFund(name: "Trip", targetMinor: 100, account: archived)
        }
    }

    @Test("Progress is clamped and absent without a target")
    func progressFraction() {
        #expect(SavingsFormatting.progressFraction(fundedMinor: 50, targetMinor: 100) == 0.5)
        #expect(SavingsFormatting.progressFraction(fundedMinor: 150, targetMinor: 100) == 1)
        #expect(SavingsFormatting.progressFraction(fundedMinor: -50, targetMinor: 100) == 0)
        #expect(SavingsFormatting.progressFraction(fundedMinor: 50, targetMinor: 0) == nil)
    }
}
