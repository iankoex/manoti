//
//  ConfirmationIngestTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Confirmation ingest")
struct ConfirmationIngestTests {
    private let paybill =
        "UKP6H2TUYY Confirmed. Ksh280.00 sent to Family Bank Pesa Pap for account 2829646 on 25/11/26 at 5:58 PM New M-PESA balance is Ksh260.68. Transaction cost, Ksh5.00.Amount you can transact within the day is 497,486.00. See all your balances now https://saf.cx/kWQpy"
    private let receipt =
        "Confirmed. Payment of Ksh. 280.00 to TABISCARE PHARMACY(2829646) has been received. Ref: UKP6H2TUYY on 25-11-2026 17:58Hrs."

    private struct Services {
        let accounts: AccountService
        let categories: CategoryService
        let inbox: InboxService
        let ingest: IngestService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()

        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        _ = try? SharedRulesService(context: context, defaults: defaults)
            .installBundledRulesIfNeeded()

        return Services(
            accounts: AccountService(context: context),
            categories: CategoryService(context: context),
            inbox: InboxService(context: context),
            ingest: IngestService(context: context),
            context: context
        )
    }

    private func mobileAccount(_ services: Services) throws -> Account {
        let account = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        try services.accounts.addIdentifier(value: "M-PESA", type: .sender, to: account)
        try services.accounts.addIdentifier(value: "254700000000", type: .phone, to: account)
        return account
    }

    private func entries(_ services: Services) throws -> [LedgerEntry] {
        try services.context.fetch(FetchDescriptor<LedgerEntry>())
            .filter { !$0.isSoftDeleted && $0.source == .message }
    }

    @Test("The receipt enriches the M-Pesa entry instead of creating a second row")
    func receiptAfterPayment() throws {
        let services = try makeServices()
        let mobile = try mobileAccount(services)

        let first = try services.ingest.ingest(text: paybill, sender: "M-PESA")
        #expect(first.status == .needsReview)
        #expect(try entries(services).count == 1)

        let second = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")
        #expect(second.status == .duplicate)

        let all = try entries(services)
        #expect(all.count == 1)

        let entry = try #require(all.first)
        #expect(entry.id == first.entryID)
        #expect(entry.payee == "TABISCARE PHARMACY")
        #expect(entry.channelName == "Family Bank Pesa Pap")
        #expect(entry.feeMinor == 500)
        #expect(entry.balanceAfterMinor == 26_068)
        #expect(entry.confirmationRef == "UKP6H2TUYY")
        #expect(entry.confirmationSender == "FAMILY BANK")
        #expect(entry.amountMinor == 28_000)
        #expect(entry.account?.id == mobile.id)
        #expect(entry.isConfirmationOnly == false)
        #expect(try services.inbox.pending().count == 1)
    }

    @Test("A receipt that arrives first is upgraded in place by the payment")
    func paymentAfterReceipt() throws {
        let services = try makeServices()
        let mobile = try mobileAccount(services)

        let first = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")
        #expect(first.status == .needsReview)

        let receiptEntry = try #require(try entries(services).first)
        #expect(receiptEntry.isConfirmationOnly)
        #expect(receiptEntry.account == nil)
        #expect(receiptEntry.payee == "TABISCARE PHARMACY")

        let second = try services.ingest.ingest(text: paybill, sender: "M-PESA")
        #expect(second.status == .needsReview)

        let all = try entries(services)
        #expect(all.count == 1)

        let entry = try #require(all.first)
        #expect(entry.id == receiptEntry.id)
        #expect(entry.account?.id == mobile.id)
        #expect(entry.feeMinor == 500)
        #expect(entry.balanceAfterMinor == 26_068)
        #expect(entry.channelName == "Family Bank Pesa Pap")
        #expect(entry.payee == "TABISCARE PHARMACY")
        #expect(entry.isConfirmationOnly == false)
    }

    @Test("A late receipt still names the merchant on a confirmed entry")
    func receiptAfterConfirmation() throws {
        let services = try makeServices()
        let mobile = try mobileAccount(services)

        _ = try services.ingest.ingest(text: paybill, sender: "M-PESA")
        let entry = try #require(try entries(services).first)

        let category = try #require(
            try services.categories.fetchGroups()
                .flatMap(\.visibleCategories)
                .first { $0.kind == .expense }
        )

        try services.inbox.confirm(entry, account: mobile, category: category)
        #expect(entry.status == .confirmed)

        _ = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")

        #expect(entry.status == .confirmed)
        #expect(entry.payee == "TABISCARE PHARMACY")
        #expect(entry.channelName == "Family Bank Pesa Pap")
        #expect(entry.primaryCategory?.id == category.id)
        #expect(entry.feeMinor == 500)
        #expect(entry.balanceAfterMinor == 26_068)
    }

    @Test("A manual rename is never replaced by the merchant name")
    func manualRenameWins() throws {
        let services = try makeServices()
        _ = try mobileAccount(services)

        _ = try services.ingest.ingest(text: paybill, sender: "M-PESA")
        let entry = try #require(try entries(services).first)
        entry.payee = "Mama's shop"
        try services.context.save()

        _ = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")

        #expect(entry.payee == "Mama's shop")
        #expect(entry.channelName == "Family Bank Pesa Pap")
        #expect(entry.confirmationRef == "UKP6H2TUYY")
    }

    @Test("An ignored entry absorbs the receipt without a new row")
    func ignoredEntryStaysIgnored() throws {
        let services = try makeServices()
        _ = try mobileAccount(services)

        _ = try services.ingest.ingest(text: paybill, sender: "M-PESA")
        let entry = try #require(try entries(services).first)
        try services.inbox.ignore(entry, reason: .duplicate)

        _ = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")

        let all = try entries(services)
        #expect(all.count == 1)
        #expect(entry.status == .ignored)
        #expect(entry.payee == "Family Bank Pesa Pap")
    }

    @Test("A repeated receipt is a duplicate")
    func repeatedReceipt() throws {
        let services = try makeServices()
        _ = try mobileAccount(services)

        _ = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")
        let second = try services.ingest.ingest(text: receipt, sender: "FAMILY BANK")

        #expect(second.status == .duplicate)
        #expect(try entries(services).count == 1)
    }

    @Test("A receipt with a different amount is not merged")
    func amountMismatch() throws {
        let services = try makeServices()
        _ = try mobileAccount(services)

        _ = try services.ingest.ingest(text: paybill, sender: "M-PESA")
        let wrong = receipt.replacingOccurrences(of: "280.00", with: "300.00")
        _ = try services.ingest.ingest(text: wrong, sender: "FAMILY BANK")

        let all = try entries(services)
        #expect(all.count == 2)
        #expect(all.contains { $0.payee == "Family Bank Pesa Pap" })
        #expect(all.contains { $0.payee == "TABISCARE PHARMACY" })
    }
}
