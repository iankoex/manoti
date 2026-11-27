//
//  CorrelationMaintenanceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Correlation maintenance")
struct CorrelationMaintenanceTests {
    private let receipt =
        "Confirmed. Payment of Ksh. 280.00 to TABISCARE PHARMACY(2829646) has been received. Ref: UKP6H2TUYY on 25-11-2026 17:58Hrs."

    private func makeContext() throws -> (ModelContext, UserDefaults) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()

        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        _ = try? SharedRulesService(context: context, defaults: defaults)
            .installBundledRulesIfNeeded()
        return (context, defaults)
    }

    @Test("Old rows gain the merchant and unreadable receipts are consumed")
    func oldReceipt() throws {
        let (context, defaults) = try makeContext()
        let accounts = AccountService(context: context)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        try accounts.addIdentifier(value: "M-PESA", type: .sender, to: mobile)

        let date = Calendar.current.date(
            from: DateComponents(year: 2026, month: 11, day: 25, hour: 17, minute: 58)
        ) ?? Date()

        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 28_000,
            feeMinor: 500,
            currencyCode: "KES",
            occurredAt: date,
            payee: "Family Bank Pesa Pap",
            source: .message
        )
        entry.account = mobile
        entry.externalRef = "UKP6H2TUYY"
        entry.balanceAfterMinor = 26_068
        entry.status = .needsReview
        context.insert(entry)

        let line = LedgerEntryLine(amountMinor: 28_000)
        context.insert(line)
        line.entry = entry
        entry.lines = [line]

        let unparsed = UnparsedMessage(
            rawText: receipt,
            sender: "FAMILY BANK",
            receivedAt: date,
            reason: "Could not read this message."
        )
        context.insert(unparsed)
        try context.save()

        let pipeline = MaintenancePipeline(context: context, defaults: defaults)
        _ = pipeline.runCorrelationRepairs()

        #expect(entry.payee == "TABISCARE PHARMACY")
        #expect(entry.channelName == "Family Bank Pesa Pap")
        #expect(entry.ingestPayee == "Family Bank Pesa Pap")
        #expect(entry.confirmationRef == "UKP6H2TUYY")
        #expect(entry.confirmationSender == "FAMILY BANK")
        #expect(try context.fetch(FetchDescriptor<UnparsedMessage>()).isEmpty)

        _ = pipeline.runCorrelationRepairs()

        #expect(try context.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.source == .message }.count == 1)
        #expect(try context.fetch(FetchDescriptor<UnparsedMessage>()).isEmpty)
    }

    @Test("Old unpaired legs are linked by reference")
    func oldTransferLegs() throws {
        let (context, defaults) = try makeContext()
        let accounts = AccountService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let date = Date()
        let out = LedgerEntry(
            kind: .transferOut,
            amountMinor: 200_000,
            currencyCode: "KES",
            occurredAt: date,
            source: .message
        )
        out.account = bank
        out.externalRef = "5989CBLR1498"
        out.counterpartRef = "UKP6H2R80I"
        out.status = .needsReview
        context.insert(out)

        let incoming = LedgerEntry(
            kind: .transferIn,
            amountMinor: 200_000,
            currencyCode: "KES",
            occurredAt: date,
            source: .message
        )
        incoming.account = mobile
        incoming.externalRef = "UKP6H2R80I"
        incoming.counterpartRef = "5989CBLR1498"
        incoming.status = .needsReview
        context.insert(incoming)
        try context.save()

        let pipeline = MaintenancePipeline(context: context, defaults: defaults)
        _ = pipeline.runCorrelationRepairs()

        let transfers = try TransferService(context: context).linkedTransfers()
        #expect(transfers.count == 1)
        #expect(out.status == .confirmed)
        #expect(incoming.status == .confirmed)

        _ = pipeline.runCorrelationRepairs()
        #expect(try TransferService(context: context).linkedTransfers().count == 1)
    }
}
