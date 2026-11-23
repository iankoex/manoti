//
//  IngestOutboxTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Ingest outbox")
struct IngestOutboxTests {
    private let paid =
        "UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Nixomb Limited - Shell Bellevue. on 21/11/26 at 11:54 AM."
        + " New M-PESA balance is Ksh939.68. Transaction cost, Ksh8.30."

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return context
    }

    private func makeOutbox() -> (IngestOutbox, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("manoti-outbox-\(UUID().uuidString)", isDirectory: true)
        return (IngestOutbox(directory: directory), directory)
    }

    @Test("A parked message survives until it is drained")
    func parking() throws {
        let (outbox, directory) = makeOutbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let message = OutboxMessage(
            text: paid,
            sender: "M-PESA",
            receivedAt: Date(),
            dedupeHash: IngestService.dedupeHash(sender: "M-PESA", text: paid)
        )
        try outbox.enqueue(message)

        #expect(outbox.count() == 1)
        #expect(try outbox.pending().first?.text == paid)
    }

    @Test("Draining records the message once and clears the receipt")
    func drain() throws {
        let (outbox, directory) = makeOutbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = try makeContext()
        let accounts = AccountService(context: context)
        _ = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let receipt = OutboxMessage(
            text: paid,
            sender: "M-PESA",
            receivedAt: Date(),
            dedupeHash: IngestService.dedupeHash(sender: "M-PESA", text: paid)
        )
        try outbox.enqueue(receipt)

        let drained = try outbox.drain(into: IngestService(context: context))

        #expect(drained == 1)
        #expect(outbox.count() == 0)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 2)
    }

    @Test("Two receipts for the same text dedupe to one ledger row")
    func replayIsIdempotent() throws {
        let (outbox, directory) = makeOutbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let context = try makeContext()
        _ = try AccountService(context: context).create(name: "M-Pesa", kind: .mobileMoney)

        let hash = IngestService.dedupeHash(sender: "M-PESA", text: paid)
        try outbox.enqueue(
            OutboxMessage(text: paid, sender: "M-PESA", receivedAt: Date(), dedupeHash: hash)
        )
        try outbox.enqueue(
            OutboxMessage(text: paid, sender: "M-PESA", receivedAt: Date(), dedupeHash: hash)
        )

        let drained = try outbox.drain(into: IngestService(context: context))

        #expect(drained == 2)
        #expect(outbox.count() == 0)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 2)
    }
}
