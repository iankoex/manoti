//
//  TransferConversionTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Transfer conversion")
struct TransferConversionTests {
    private func makeServices() throws -> (AccountService, TransferService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return (
            AccountService(context: context),
            TransferService(context: context),
            context
        )
    }

    private func income(
        account: Account,
        amountMinor: Int64,
        reference: String? = "UKP6H2R80I",
        in context: ModelContext
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            kind: .income,
            amountMinor: amountMinor,
            currencyCode: account.currencyCode,
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            payee: "IM BANK LIMITED- APP",
            source: .message
        )
        entry.account = account
        entry.externalRef = reference ?? ""
        entry.rawMessage = "Original message"
        entry.status = .needsReview
        context.insert(entry)
        entry.attachSingleLine(category: nil, in: context)
        return entry
    }

    @Test("An income becomes the in-leg and keeps its message identity")
    func incomeToTransfer() throws {
        let (accounts, transfers, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let entry = income(account: mobile, amountMinor: 200_000, in: context)
        let originalID = entry.id
        try context.save()

        let transfer = try transfers.convert(
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

        #expect(entry.id == originalID)
        #expect(entry.kind == .transferIn)
        #expect(entry.account?.id == mobile.id)
        #expect(entry.amountMinor == 200_000)
        #expect(entry.feeMinor == 0)
        #expect(entry.orderedLines.isEmpty)
        #expect(entry.externalRef == "UKP6H2R80I")
        #expect(entry.rawMessage == "Original message")
        #expect(entry.status == .confirmed)
        #expect(entry.transfer?.id == transfer.id)

        #expect(transfer.outTransaction?.account?.id == bank.id)
        #expect(transfer.outTransaction?.amountMinor == 200_000)
        #expect(transfer.outTransaction?.source == .manual)
        #expect(transfer.inTransaction?.id == entry.id)
        #expect(transfer.outTransaction?.status == .confirmed)
        #expect(try InboxService(context: context).pending().isEmpty)
        #expect(try context.fetch(FetchDescriptor<MerchantMemory>()).isEmpty)
    }

    @Test("An expense becomes the out-leg and carries the fee")
    func expenseToTransfer() throws {
        let (accounts, transfers, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)

        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 28_000,
            feeMinor: 500,
            currencyCode: "KES",
            occurredAt: Date(timeIntervalSince1970: 1_790_000_000),
            payee: "Family Bank Pesa Pap",
            source: .message
        )
        entry.account = mobile
        entry.externalRef = "UKP6H2TUYY"
        entry.status = .needsReview
        context.insert(entry)

        let category = try #require(
            try CategoryService(context: context).fetchCategories().first { $0.kind == .expense }
        )
        entry.attachSingleLine(category: category, in: context)
        try context.save()

        let transfer = try transfers.convert(
            entry: entry,
            source: mobile,
            destination: bank,
            amountOutMinor: 28_000,
            amountInMinor: 28_000,
            feeMinor: 500,
            occurredAt: entry.occurredAt,
            payee: entry.payee,
            note: "Pharmacy"
        )

        #expect(entry.kind == .transferOut)
        #expect(entry.account?.id == mobile.id)
        #expect(entry.feeMinor == 500)
        #expect(entry.orderedLines.isEmpty)
        #expect(entry.externalRef == "UKP6H2TUYY")
        #expect(entry.transfer?.id == transfer.id)
        #expect(transfer.inTransaction?.account?.id == bank.id)
        #expect(transfer.inTransaction?.amountMinor == 28_000)
        #expect(transfer.inTransaction?.feeMinor == 0)
        #expect(transfer.fee?.minorUnits == 500)
    }

    @Test("A same-currency mismatch is refused before anything changes")
    func mismatchRefused() throws {
        let (accounts, transfers, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let entry = income(account: mobile, amountMinor: 200_000, in: context)
        try context.save()

        #expect(throws: TransferError.amountMismatch) {
            try transfers.convert(
                entry: entry,
                source: bank,
                destination: mobile,
                amountOutMinor: 200_000,
                amountInMinor: 199_000,
                feeMinor: 0,
                occurredAt: entry.occurredAt,
                payee: entry.payee,
                note: ""
            )
        }

        #expect(entry.kind == .income)
        #expect(entry.transfer == nil)
        #expect(entry.orderedLines.count == 1)
    }

    @Test("A cross-currency conversion needs the received amount and records a rate")
    func crossCurrency() throws {
        let (accounts, transfers, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")
        let entry = income(account: mobile, amountMinor: 200_000, in: context)
        try context.save()

        let transfer = try transfers.convert(
            entry: entry,
            source: bank,
            destination: mobile,
            amountOutMinor: 1_500,
            amountInMinor: 200_000,
            feeMinor: 0,
            occurredAt: entry.occurredAt,
            payee: entry.payee,
            note: ""
        )

        #expect(entry.kind == .transferIn)
        #expect(transfer.outTransaction?.amountMinor == 1_500)
        #expect(transfer.inTransaction?.amountMinor == 200_000)
        #expect(transfer.rate != nil)

        #expect(throws: TransferError.amountInRequired) {
            let second = income(account: mobile, amountMinor: 100, in: context)
            try context.save()
            try transfers.convert(
                entry: second,
                source: bank,
                destination: mobile,
                amountOutMinor: 100,
                amountInMinor: nil,
                feeMinor: 0,
                occurredAt: second.occurredAt,
                payee: second.payee,
                note: ""
            )
        }
    }

    @Test("A linked entry cannot be converted again")
    func linkedRefused() throws {
        let (accounts, transfers, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let entry = income(account: mobile, amountMinor: 200_000, in: context)
        try context.save()

        _ = try transfers.convert(
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

        #expect(throws: TransferError.alreadyLinked) {
            try transfers.convert(
                entry: entry,
                source: mobile,
                destination: bank,
                amountOutMinor: 200_000,
                amountInMinor: 200_000,
                feeMinor: 0,
                occurredAt: entry.occurredAt,
                payee: entry.payee,
                note: ""
            )
        }
    }
}
