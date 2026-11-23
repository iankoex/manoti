//
//  IngestServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("IngestService")
struct IngestServiceTests {
    private let paid =
        "UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Nixomb Limited - Shell Bellevue. on 21/11/26 at 11:54 AM.New M-PESA balance is Ksh939.68. Transaction cost, Ksh8.30."
    private let received =
        "UKJME2X5ZR Confirmed.You have received Ksh100.00 from BRENDAH  MBINYA 0746***702 on 19/11/26 at 3:07 PM  New M-PESA balance is Ksh1,744.98."
    private let bankOut =
        "Bank to M-PESA transfer of KES 600.00 to 254700000000 - IAN KIPRONO successfully processed. Transaction Ref ID: 5951WTXH3777. M-PESA Ref ID: UKK6H292PF."
    private let pesalink =
        "Dear Customer,You have received KES 5000 via PesaLink into Acc 01234567890123 Tran Ref 000300572026112108351801173354. For enquiry,call 020 3221000. IM Bank."
    private let card =
        "Dear IAN, You made a purchase ofKES 766.00 on 2026-11-19 17:42:06 at QUICK MART LIMITED using I&M 5477********7653."

    private func makeServices() throws -> (AccountService, IngestService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return (AccountService(context: context), IngestService(context: context), context)
    }

    private func entry(for outcome: IngestOutcome, in context: ModelContext) throws -> LedgerEntry? {
        guard let id = outcome.entryID else {
            return nil
        }

        let all = try context.fetch(FetchDescriptor<LedgerEntry>())
        return all.first { $0.id == id }
    }

    @Test("A single account receives an unrouted message")
    func singleAccountFallback() throws {
        let (accounts, ingest, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let outcome = try ingest.ingest(text: paid, sender: "M-PESA")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(outcome.status == .needsReview)
        #expect(stored.kind == .expense)
        #expect(stored.amountMinor == 151_000)
        #expect(stored.feeMinor == 830)
        #expect(stored.account?.id == mobile.id)
        #expect(stored.externalRef == "UKL6H2AF65")
        #expect(stored.balanceAfterMinor == 93_968)
        #expect(stored.dedupeHash.isEmpty == false)
    }

    @Test("Identifiers route each message to the right account")
    func identifierRouting() throws {
        let (accounts, ingest, context) = try makeServices()

        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)

        try accounts.addIdentifier(value: "254700000000", type: .phone, to: mobile)
        try accounts.addIdentifier(value: "01234567890123", type: .accountNumber, to: bank)
        try accounts.addIdentifier(value: "IM BANK", type: .sender, to: bank)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)

        let bankIn = try #require(try entry(for: try ingest.ingest(text: bankOut, sender: "IM BANK"), in: context))
        #expect(bankIn.account?.id == bank.id)
        #expect(bankIn.kind == .transferOut)

        let pesalinkIn = try #require(try entry(for: try ingest.ingest(text: pesalink, sender: "IM BANK"), in: context))
        #expect(pesalinkIn.account?.id == bank.id)
        #expect(pesalinkIn.kind == .income)

        let cardIn = try #require(try entry(for: try ingest.ingest(text: card, sender: "IM BANK"), in: context))
        #expect(cardIn.account?.id == cardAccount.id)
        #expect(cardIn.kind == .expense)
        #expect(cardIn.amountMinor == 76_600)
    }

    @Test("A payee cannot hijack routing with another account's digits")
    func payeeDoesNotRoute() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let card = try accounts.create(name: "Card", kind: .card)
        try accounts.addIdentifier(value: "6702", type: .cardLast4, to: card)

        let outcome = try ingest.ingest(text: received, sender: "M-PESA")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(stored.account == nil)
        #expect(stored.status == .needsReview)
    }

    @Test("A message is never attached to an account in another currency")
    func currencyMismatchStaysInReview() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "UGX wallet", kind: .mobileMoney, currencyCode: "UGX")

        let outcome = try ingest.ingest(text: paid, sender: "M-PESA")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(stored.account == nil)
        #expect(stored.status == .needsReview)
        #expect(stored.currencyCode == "KES")
    }

    @Test("An unmatched account hint is not overridden by the single-account fallback")
    func unmatchedHintStaysInReview() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let outcome = try ingest.ingest(text: pesalink, sender: "IM BANK")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(stored.account == nil)
        #expect(stored.status == .needsReview)
    }

    @Test("With several accounts and no match, the entry waits in review")
    func ambiguousStaysInReview() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        try accounts.create(name: "Bank", kind: .bank)

        let outcome = try ingest.ingest(text: received, sender: "M-PESA")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(outcome.status == .needsReview)
        #expect(stored.status == .needsReview)
        #expect(stored.account == nil)
    }

    @Test("The same message twice is recorded once")
    func dedupe() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let first = try ingest.ingest(text: received, sender: "M-PESA")
        let second = try ingest.ingest(text: received, sender: "M-PESA")

        #expect(first.status == .needsReview)
        #expect(second.status == .duplicate)

        let count = try context.fetchCount(FetchDescriptor<LedgerEntry>())
        #expect(count == 2)  // opening balance + one message
    }

    @Test("A trusted merchant auto-files and learns nothing new")
    func autoApplyMerchant() throws {
        let (accounts, ingest, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let category = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )

        let memory = MerchantMemory(
            merchantKey: MerchantKey.normalise("Nixomb Limited - Shell Bellevue"),
            displayName: "Shell Bellevue"
        )
        memory.category = category
        memory.autoApply = true
        context.insert(memory)
        try context.save()

        let outcome = try ingest.ingest(text: paid, sender: "M-PESA")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(outcome.status == .recorded)
        #expect(stored.status == .confirmed)
        #expect(stored.category?.id == category.id)
        #expect(stored.account?.id == mobile.id)
    }

    @Test("An untrusted memory suggests but still waits in the Inbox")
    func untrustedMerchantStaysInReview() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let category = try #require(
            try context.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Fuel" }
        )

        let memory = MerchantMemory(
            merchantKey: MerchantKey.normalise("Nixomb Limited - Shell Bellevue"),
            displayName: "Shell Bellevue"
        )
        memory.category = category
        memory.autoApply = false
        context.insert(memory)
        try context.save()

        let outcome = try ingest.ingest(text: paid, sender: "M-PESA")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(outcome.status == .needsReview)
        #expect(stored.status == .needsReview)
        #expect(stored.account != nil)
    }

    @Test("Unrecognised text is kept for review, not posted")
    func unrecognised() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let outcome = try ingest.ingest(text: "Good morning", sender: "M-PESA")

        #expect(outcome.status == .unrecognised)
        #expect(outcome.unparsedID != nil)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<UnparsedMessage>()) == 1)

        let again = try ingest.ingest(text: "Good morning", sender: "M-PESA")
        #expect(again.unparsedID == outcome.unparsedID)
        #expect(try context.fetchCount(FetchDescriptor<UnparsedMessage>()) == 1)
    }

    @Test("A trailing newline still dedupes a known message")
    func dedupeWhitespace() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let first = try ingest.ingest(text: received, sender: "M-PESA")
        let second = try ingest.ingest(text: received + "\n", sender: "M-PESA ")

        #expect(first.status == .needsReview)
        #expect(second.status == .duplicate)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 2)
    }

    @Test("A transfer out without a counterpart reference is flagged for linking")
    func transferNeedsLinking() throws {
        let (accounts, ingest, context) = try makeServices()
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        try accounts.addIdentifier(value: "7890123", type: .accountNumber, to: bank)
        try accounts.addIdentifier(value: "IM BANK", type: .sender, to: bank)

        let own =
            "Transfer to Own Account of KES 16,700.00 to IAN KIPRONO A/c 7890123 on 19/11/2026 12:29 processed successfully. Transaction Ref ID: 431567921248."
        let outcome = try ingest.ingest(text: own, sender: "IM BANK")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(stored.kind == .transferOut)
        #expect(stored.status == .needsReview)
        #expect(stored.account?.id == bank.id)
    }

    @Test("A message counterpart reference is stored without changing the external reference")
    func counterpartReferenceStored() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let outcome = try ingest.ingest(text: bankOut, sender: "IM BANK")
        let stored = try #require(try entry(for: outcome, in: context))

        #expect(stored.externalRef == "5951WTXH3777")
        #expect(stored.counterpartRef == "UKK6H292PF")
    }

    @Test("Turning off raw retention keeps parsing but drops the message text")
    func rawMessageRetention() throws {
        let (accounts, ingest, context) = try makeServices()
        try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let appService = AppService(context: context)

        #expect(appService.keepRawMessages)

        let keptOutcome = try ingest.ingest(text: paid, sender: "M-PESA")
        let kept = try #require(try entry(for: keptOutcome, in: context))
        #expect(kept.rawMessage == paid)

        try appService.setKeepRawMessages(false)

        let droppedOutcome = try ingest.ingest(text: received, sender: "M-PESA")
        let dropped = try #require(try entry(for: droppedOutcome, in: context))

        #expect(dropped.rawMessage.isEmpty)
        #expect(dropped.payee.contains("BRENDAH"))
        #expect(dropped.amountMinor == 10_000)
        #expect(dropped.externalRef == "UKJME2X5ZR")
        #expect(dropped.messageSender == "M-PESA")
    }
}
