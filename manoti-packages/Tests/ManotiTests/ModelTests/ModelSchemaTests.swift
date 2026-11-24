//
//  ModelSchemaTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels

@MainActor
@Suite("Model schema")
struct ModelSchemaTests {
    @Test("An in-memory container persists every model in the schema")
    func containerRoundTrip() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        let account = Account(name: "M-Pesa", kind: .mobileMoney)
        context.insert(account)

        let group = CategoryGroup(name: "Food", symbolName: "fork.knife", colorHex: "#FF9500")
        context.insert(group)

        let category = SpendingCategory(name: "Lunch", symbolName: "takeoutbag.and.cup.and.straw", colorHex: "#FF9500")
        category.group = group
        context.insert(category)

        let transaction = LedgerEntry(kind: .expense, amountMinor: 10_000, payee: "Cafe")
        transaction.account = account
        transaction.category = category
        context.insert(transaction)

        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.transactions?.count == 1)
        #expect(accounts.first?.transactions?.first?.category?.name == "Lunch")
        #expect(group.categories?.count == 1)
    }

    @Test("The default schema contains every designed model")
    func schemaContents() {
        let expected: [any PersistentModel.Type] = [
            Account.self,
            AccountIdentifier.self,
            LedgerEntry.self,
            Transfer.self,
            CategoryGroup.self,
            SpendingCategory.self,
            ExchangeRateRecord.self,
            AppSettings.self,
            ParseRuleSet.self,
            ParseRule.self,
            MerchantMemory.self,
            MerchantAlias.self,
            IngestMemory.self,
            SmartRule.self,
            ContextWindow.self,
            Loan.self,
            Investment.self,
            InvestmentCashFlow.self,
            BudgetPeriod.self,
            Envelope.self,
            SinkingFund.self,
            SinkingFundContribution.self,
            Goal.self,
            BudgetAlert.self,
            ReconcileSession.self,
            ReconcileMessage.self,
            UnparsedMessage.self,
        ]

        #expect(ManotiSchema.models.count == expected.count)
        for type in expected {
            #expect(ManotiSchema.models.contains { $0 == type })
        }
    }

    /// CloudKit refuses to load a container when any relationship lacks an inverse.
    @Test("Every relationship declares an inverse")
    func relationshipsHaveInverses() {
        let schema = Schema(ManotiSchema.models)

        var problems: [String] = []
        for entity in schema.entities {
            for relationship in entity.relationships {
                let label = "\(entity.name).\(relationship.name)"
                guard let inverseName = relationship.inverseName else {
                    problems.append("\(label) has no inverse")
                    continue
                }

                let destination = schema.entitiesByName[relationship.destination]
                let inverse = destination?.relationshipsByName[inverseName]
                if inverse?.inverseName != relationship.name {
                    problems.append(
                        "\(label) points at \(relationship.destination).\(inverseName), which does not point back"
                    )
                }
            }
        }

        #expect(problems.isEmpty, "Relationship problems: \(problems.joined(separator: ", "))")
    }

    @Test("An account exposes its currency and display name")
    func accountCurrency() {
        let account = Account(name: "USD Bank", kind: .bank, currencyCode: "USD")

        #expect(account.currency.code == "USD")
        #expect(account.currency.exponent == 2)
        #expect(account.displayName == "USD Bank")

        let unnamed = Account(name: "", kind: .cash)
        #expect(unnamed.displayName == "Cash")
    }
}
