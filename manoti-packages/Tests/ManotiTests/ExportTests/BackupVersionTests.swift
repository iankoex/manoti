//
//  BackupVersionTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Backup versions")
struct BackupVersionTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    private func makeSource() throws -> (ModelContext, Account, AppModels.Tag) {
        let context = try makeContext()
        try SeedService(context: context).seedIfNeeded()
        let accounts = AccountService(context: context)
        let account = try accounts.create(name: "Acme Ltd", kind: .bank)
        account.ownership = .company
        try context.save()

        let tag = AppModels.Tag(name: "INV-4471", colorHex: "#27AE60", symbolName: "doc.text")
        context.insert(tag)

        let categories = try CategoryService(context: context).fetchCategories()
        let supplies = try #require(categories.first { $0.name == "Household" })
        let groceries = try #require(categories.first { $0.name == "Groceries" })

        _ = try LedgerService(context: context).record(
            kind: .expense,
            amountMinor: 50_000,
            account: account,
            lines: [
                LedgerLineInput(amountMinor: 30_000, category: supplies, tags: [tag]),
                LedgerLineInput(amountMinor: 20_000, category: groceries),
            ],
            payee: "Supermarket"
        )

        try context.save()
        return (context, account, tag)
    }

    @Test("Version 2 restores split lines, tags and account ownership")
    func v2RoundTrip() throws {
        let (source, _, _) = try makeSource()
        let data = try ExportService(context: source).backupData()

        let target = try makeContext()
        let summary = try ExportService(context: target).restore(data: data)

        #expect(summary.skipped == 0)

        let entries = try target.fetch(FetchDescriptor<LedgerEntry>())
        let entry = try #require(entries.first { $0.payee == "Supermarket" })
        #expect(entry.orderedLines.count == 2)
        #expect(entry.orderedLines.map(\.amountMinor) == [30_000, 20_000])
        #expect(entry.orderedLines.first?.category?.name == "Household")
        #expect(entry.orderedLines.first?.tagList.map(\.name) == ["INV-4471"])
        #expect(entry.orderedLines.last?.category?.name == "Groceries")

        let accounts = try target.fetch(FetchDescriptor<Account>())
        #expect(accounts.first?.ownership == .company)
        #expect(try target.fetch(FetchDescriptor<AppModels.Tag>()).count == 1)
    }

    @Test("Backups round-trip the confirmation and channel fields")
    func confirmationRoundTrip() throws {
        let (source, _, _) = try makeSource()
        let entry = try #require(
            try source.fetch(FetchDescriptor<LedgerEntry>())
                .first { $0.payee == "Supermarket" }
        )

        let confirmedAt = Date(timeIntervalSince1970: 1_790_000_000)
        entry.ingestPayee = "Family Bank Pesa Pap"
        entry.channelName = "Family Bank Pesa Pap"
        entry.confirmationRef = "UKP6H2TUYY"
        entry.confirmationSender = "FAMILY BANK"
        entry.confirmedAt = confirmedAt
        entry.confirmationText = "Confirmed. Payment received."
        entry.isConfirmationOnly = true
        try source.save()

        let data = try ExportService(context: source).backupData()
        let target = try makeContext()
        _ = try ExportService(context: target).restore(data: data)

        let restored = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>())
                .first { $0.payee == "Supermarket" }
        )

        #expect(restored.ingestPayee == "Family Bank Pesa Pap")
        #expect(restored.channelName == "Family Bank Pesa Pap")
        #expect(restored.confirmationRef == "UKP6H2TUYY")
        #expect(restored.confirmationSender == "FAMILY BANK")
        #expect(restored.confirmedAt == confirmedAt)
        #expect(restored.confirmationText == "Confirmed. Payment received.")
        #expect(restored.isConfirmationOnly)
    }

    @Test("Version 1 restores one synthesised line from the entry category")
    func v1RestoresSingleLine() throws {
        let (source, _, _) = try makeSource()
        let v2Data = try ExportService(context: source).backupData()

        let categories = try CategoryService(context: source).fetchCategories()
        let supplies = try #require(categories.first { $0.name == "Household" })

        var object = try #require(
            try JSONSerialization.jsonObject(with: v2Data) as? [String: Any]
        )
        object["schemaVersion"] = 1
        object.removeValue(forKey: "checksum")
        object.removeValue(forKey: "lines")
        object.removeValue(forKey: "tags")

        var entries = try #require(object["ledgerEntries"] as? [[String: Any]])

        for index in entries.indices where entries[index]["payee"] as? String == "Supermarket" {
            entries[index]["categoryID"] = supplies.id.uuidString
        }

        object["ledgerEntries"] = entries

        let v1Data = try JSONSerialization.data(withJSONObject: object)

        let target = try makeContext()
        _ = try ExportService(context: target).restore(data: v1Data)

        let restored = try target.fetch(FetchDescriptor<LedgerEntry>())
        let entry = try #require(restored.first { $0.payee == "Supermarket" })
        #expect(entry.orderedLines.count == 1)
        #expect(entry.orderedLines.first?.amountMinor == 50_000)
        #expect(entry.orderedLines.first?.category?.name == "Household")
        #expect(try target.fetch(FetchDescriptor<AppModels.Tag>()).isEmpty)
    }

    @Test("Restoring over an edited split entry replaces its lines")
    func restoreReplacesExistingLines() throws {
        let (source, _, _) = try makeSource()
        let data = try ExportService(context: source).backupData()

        let target = try makeContext()
        let service = ExportService(context: target)
        _ = try service.restore(data: data)

        let entries = try target.fetch(FetchDescriptor<LedgerEntry>())
        let entry = try #require(entries.first { $0.payee == "Supermarket" })
        let extra = LedgerEntryLine(amountMinor: 1_000)
        target.insert(extra)
        extra.entry = entry
        entry.lines = (entry.lines ?? []) + [extra]
        try target.save()

        _ = try service.restore(data: data)

        #expect(entry.orderedLines.count == 2)
        #expect(entry.orderedLines.reduce(Int64(0)) { $0 + $1.amountMinor } == entry.amountMinor)
    }

    @Test("The backup summary mentions tags")
    func summaryMentionsTags() throws {
        let (source, _, _) = try makeSource()
        let data = try ExportService(context: source).backupData()
        #expect(try ExportService(context: source).backupSummary(data: data).contains("tag"))
    }

    @Test("An unknown backup version is rejected")
    func unknownVersion() throws {
        let (source, _, _) = try makeSource()
        let data = try ExportService(context: source).backupData()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 99
        object.removeValue(forKey: "checksum")
        let bumped = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: ExportError.unsupportedVersion(99)) {
            try ExportService(context: try makeContext()).restore(data: bumped)
        }
    }

    @Test("CSV carries the joined category names and a tags column")
    func csvColumns() throws {
        let (source, _, _) = try makeSource()
        let csv = try ExportService(context: source).transactionsCSV()
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)

        #expect(lines[0].contains(",category,tags,payee,"))
        #expect(lines[1].contains("Household | Groceries"))
        #expect(lines[1].contains("INV-4471"))
    }
}
