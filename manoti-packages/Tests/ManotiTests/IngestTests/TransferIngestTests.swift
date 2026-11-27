//
//  TransferIngestTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Transfer ingest")
struct TransferIngestTests {
    private let bankOut =
        "Bank to M-PESA transfer of KES 2,000.00 to 254700000000 - IAN KIPRONO successfully processed. Transaction Ref ID: 5989CBLR1498. M-PESA Ref ID: UKP6H2R80I."
    private let mpesaIn =
        "UKP6H2R80I Confirmed. You have received Ksh2,000.00 from IM BANK LIMITED- APP on 25/11/26 at 7:31 AM. New M-PESA balance is Ksh2,511.68. Buy goods with M-PESA."

    private struct Services {
        let accounts: AccountService
        let inbox: InboxService
        let transfers: TransferService
        let ingest: IngestService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()

        return Services(
            accounts: AccountService(context: context),
            inbox: InboxService(context: context),
            transfers: TransferService(context: context),
            ingest: IngestService(context: context),
            context: context
        )
    }

    private func accounts(_ services: Services, phone: String?) throws -> (bank: Account, mobile: Account) {
        let bank = try services.accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try services.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        try services.accounts.addIdentifier(value: "IM BANK", type: .sender, to: bank)
        try services.accounts.addIdentifier(value: "M-PESA", type: .sender, to: mobile)

        if let phone {
            try services.accounts.addIdentifier(value: phone, type: .phone, to: mobile)
        }

        return (bank, mobile)
    }

    private func entries(_ services: Services) throws -> [LedgerEntry] {
        try services.context.fetch(FetchDescriptor<LedgerEntry>())
            .filter { !$0.isSoftDeleted && $0.source == .message }
    }

    @Test("Bank first builds the M-Pesa leg from the phone and links one transfer")
    func bankFirst() throws {
        let services = try makeServices()
        let (bank, mobile) = try accounts(services, phone: "254700000000")

        let first = try services.ingest.ingest(text: bankOut, sender: "IM BANK")
        #expect(first.status == .recorded)

        let transfers = try services.transfers.linkedTransfers()
        #expect(transfers.count == 1)

        let transfer = try #require(transfers.first)
        #expect(transfer.outTransaction?.account?.id == bank.id)
        #expect(transfer.inTransaction?.account?.id == mobile.id)
        #expect(transfer.outTransaction?.status == .confirmed)
        #expect(transfer.inTransaction?.status == .confirmed)
        #expect(transfer.inTransaction?.externalRef == "UKP6H2R80I")
        #expect(try services.inbox.pending().isEmpty)
        #expect(try entries(services).count == 2)

        let second = try services.ingest.ingest(text: mpesaIn, sender: "M-PESA")
        #expect(second.status == .duplicate)
        #expect(try services.transfers.linkedTransfers().count == 1)
        #expect(try entries(services).count == 2)
        #expect(transfer.inTransaction?.balanceAfterMinor == 251_168)
    }

    @Test("M-Pesa first leaves one leg, then the bank message links it")
    func mpesaFirst() throws {
        let services = try makeServices()
        let (bank, mobile) = try accounts(services, phone: "254700000000")

        _ = try services.ingest.ingest(text: mpesaIn, sender: "M-PESA")
        #expect(try services.transfers.linkedTransfers().isEmpty)

        let second = try services.ingest.ingest(text: bankOut, sender: "IM BANK")
        #expect(second.status == .recorded)

        let transfers = try services.transfers.linkedTransfers()
        #expect(transfers.count == 1)

        let transfer = try #require(transfers.first)
        #expect(transfer.outTransaction?.account?.id == bank.id)
        #expect(transfer.inTransaction?.account?.id == mobile.id)
        #expect(try services.inbox.pending().isEmpty)
        #expect(try entries(services).count == 2)
    }

    @Test("Bank only without a matching phone stays unpaired")
    func bankOnlyUnmatched() throws {
        let services = try makeServices()
        _ = try accounts(services, phone: nil)

        let outcome = try services.ingest.ingest(text: bankOut, sender: "IM BANK")
        #expect(outcome.status == .needsReview)
        #expect(try services.transfers.unpairedLegs().count == 1)
        #expect(try services.inbox.pending().count == 1)
    }

    @Test("A bank message later attaches to a transfer converted by hand")
    func laterMessageAttaches() throws {
        let services = try makeServices()
        let (bank, mobile) = try accounts(services, phone: nil)

        let entry = LedgerEntry(
            kind: .income,
            amountMinor: 200_000,
            currencyCode: "KES",
            occurredAt: Date(),
            payee: "IM BANK LIMITED- APP",
            source: .message
        )
        entry.account = mobile
        entry.externalRef = "UKP6H2R80I"
        entry.status = .needsReview
        services.context.insert(entry)
        entry.attachSingleLine(category: nil, in: services.context)
        try services.context.save()

        _ = try services.transfers.convert(
            entry: entry,
            source: bank,
            destination: mobile,
            amountOutMinor: 200_000,
            amountInMinor: 200_000,
            feeMinor: 0,
            occurredAt: entry.occurredAt,
            payee: entry.payee,
            note: ""
        )

        let outLeg = try #require(entry.transfer?.outTransaction)
        let before = try entries(services).count

        let outcome = try services.ingest.ingest(text: bankOut, sender: "IM BANK")

        #expect(outcome.status == .duplicate)
        #expect(try entries(services).count == before)
        #expect(try services.transfers.linkedTransfers().count == 1)
        #expect(outLeg.externalRef == "5989CBLR1498")
        #expect(outLeg.counterpartRef == "UKP6H2R80I")
        #expect(outLeg.status == .confirmed)
        #expect(outLeg.rawMessage.isEmpty == false)
    }

    @Test("A locally written phone number still recognises the wallet")
    func localPhoneFormat() throws {
        let services = try makeServices()
        _ = try accounts(services, phone: "0700 000 000")

        let outcome = try services.ingest.ingest(text: bankOut, sender: "IM BANK")
        #expect(outcome.status == .recorded)
        #expect(try services.transfers.linkedTransfers().count == 1)
    }
}
