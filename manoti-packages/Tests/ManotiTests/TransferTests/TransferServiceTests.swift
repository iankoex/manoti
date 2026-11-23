//
//  TransferServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("TransferService")
struct TransferServiceTests {
    private func makeServices() throws -> (AccountService, TransferService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (AccountService(context: context), TransferService(context: context), context)
    }

    @Test("A same-currency transfer moves the amount and charges the fee once")
    func sameCurrency() throws {
        let (accounts, transfers, _) = try makeServices()
        let bank = try accounts.create(name: "IM Bank", kind: .bank, openingBalanceMinor: 200_000)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let transfer = try transfers.transfer(
            from: bank,
            to: mobile,
            amountOutMinor: 100_000,
            feeMinor: 2_500
        )

        #expect(bank.balance.minorUnits == 97_500)
        #expect(mobile.balance.minorUnits == 100_000)
        #expect(transfer.outTransaction?.feeMinor == 2_500)
        #expect(transfer.inTransaction?.feeMinor == 0)
        #expect(transfer.legs?.count == 2)
        #expect(transfer.fromAccount?.id == bank.id)
        #expect(transfer.toAccount?.id == mobile.id)
    }

    @Test("Linking a cross-currency pair records and then removes its rate")
    func linkPairsAndRates() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let kes = try accounts.create(name: "KES Bank", kind: .bank, openingBalanceMinor: 1_000_000)
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        let out = try ledger.record(kind: .transferOut, amountMinor: 1_000_000, account: kes)
        let inbound = try ledger.record(kind: .transferIn, amountMinor: 7_750, account: usd)

        let transfer = try transfers.link(outLeg: out, inLeg: inbound)
        #expect(transfer.fromAccount?.id == kes.id)
        #expect(transfer.toAccount?.id == usd.id)

        let rates = try context.fetch(FetchDescriptor<ExchangeRateRecord>())
        #expect(rates.count == 1)
        #expect(rates.first?.source == .transfer)

        try transfers.unlink(transfer)
        #expect(try context.fetchCount(FetchDescriptor<ExchangeRateRecord>()) == 0)
        #expect(out.transfer == nil)
        #expect(inbound.transfer == nil)
    }

    @Test("Deleting a transfer soft-deletes both legs")
    func deleteTransfer() throws {
        let (accounts, transfers, context) = try makeServices()
        let bank = try accounts.create(name: "IM Bank", kind: .bank, openingBalanceMinor: 200_000)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let transfer = try transfers.transfer(from: bank, to: mobile, amountOutMinor: 100_000)
        try transfers.delete(transfer)

        #expect(try transfers.linkedTransfers().isEmpty)
        #expect(bank.balance.minorUnits == 200_000)
        #expect(mobile.balance.minorUnits == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transfer>()) == 0)
    }

    @Test("A cross-currency transfer stores both real amounts and the rate")
    func crossCurrency() throws {
        let (accounts, transfers, context) = try makeServices()
        let kes = try accounts.create(name: "KES Bank", kind: .bank, openingBalanceMinor: 1_000_000)
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        try transfers.transfer(
            from: kes,
            to: usd,
            amountOutMinor: 1_000_000,
            amountInMinor: 7_750,
            feeMinor: 5_000
        )

        #expect(kes.balance.minorUnits == -5_000)
        #expect(usd.balance.minorUnits == 7_750)

        let rates = try context.fetch(FetchDescriptor<ExchangeRateRecord>())
        #expect(rates.count == 1)
        #expect(rates.first?.source == .transfer)
        #expect(abs((rates.first?.rateScaled ?? 0) - 7_750) <= 1)
    }

    @Test("Cross-currency without an incoming amount is rejected")
    func crossCurrencyRequiresAmountIn() throws {
        let (accounts, transfers, _) = try makeServices()
        let kes = try accounts.create(name: "KES Bank", kind: .bank)
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")

        #expect(throws: TransferError.amountInRequired) {
            try transfers.transfer(from: kes, to: usd, amountOutMinor: 100_000)
        }
    }

    @Test("Same-currency with a different incoming amount is rejected")
    func sameCurrencyMismatch() throws {
        let (accounts, transfers, _) = try makeServices()
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        #expect(throws: TransferError.amountMismatch) {
            try transfers.transfer(from: bank, to: mobile, amountOutMinor: 100_000, amountInMinor: 99_000)
        }
    }

    @Test("Transferring to the same account is rejected")
    func sameAccount() throws {
        let (accounts, transfers, _) = try makeServices()
        let bank = try accounts.create(name: "IM Bank", kind: .bank)

        #expect(throws: TransferError.sameAccount) {
            try transfers.transfer(from: bank, to: bank, amountOutMinor: 100)
        }
    }

    @Test("Linking and unlinking existing legs round-trips")
    func linkAndUnlink() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank, openingBalanceMinor: 200_000)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let out = try ledger.record(kind: .transferOut, amountMinor: 50_000, account: bank)
        let inbound = try ledger.record(kind: .transferIn, amountMinor: 50_000, account: mobile)

        let transfer = try transfers.link(outLeg: out, inLeg: inbound)
        #expect(transfer.outTransaction?.id == out.id)
        #expect(out.transfer != nil)
        #expect(try context.fetchCount(FetchDescriptor<Transfer>()) == 1)

        try transfers.unlink(transfer)
        #expect(out.transfer == nil)
        #expect(inbound.transfer == nil)
        #expect(try context.fetchCount(FetchDescriptor<Transfer>()) == 0)
    }

    @Test("Unpaired legs exclude linked, deleted and ignored rows but keep review rows")
    func unpairedLegs() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let linkedOut = try ledger.record(kind: .transferOut, amountMinor: 10_000, account: bank)
        let linkedIn = try ledger.record(kind: .transferIn, amountMinor: 10_000, account: mobile)
        _ = try transfers.link(outLeg: linkedOut, inLeg: linkedIn)

        let review = try ledger.record(kind: .transferOut, amountMinor: 20_000, account: bank)
        review.status = .needsReview

        let ignored = try ledger.record(kind: .transferIn, amountMinor: 30_000, account: mobile)
        ignored.status = .ignored

        let deleted = try ledger.record(kind: .transferOut, amountMinor: 40_000, account: bank)
        try ledger.delete(deleted)

        try context.save()

        let unpaired = try transfers.unpairedLegs()
        #expect(unpaired.map(\.id) == [review.id])
    }

    @Test("Unpaired legs are newest first")
    func unpairedLegsAreSorted() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let older = try ledger.record(
            kind: .transferOut, amountMinor: 1_000, account: bank, occurredAt: Date(timeIntervalSince1970: 1_000))
        let newer = try ledger.record(
            kind: .transferIn, amountMinor: 2_000, account: mobile, occurredAt: Date(timeIntervalSince1970: 2_000))

        #expect(try transfers.unpairedLegs().map(\.id) == [newer.id, older.id])
    }

    @Test("A shared reference pairs legs across currencies and any time gap")
    func referenceCandidateAcrossCurrencies() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let kes = try accounts.create(name: "KES Bank", kind: .bank)
        let usd = try accounts.create(name: "USD Bank", kind: .bank, currencyCode: "USD")
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: kes, occurredAt: base)
        out.counterpartRef = "MPESA-REF"

        let inbound = try ledger.record(
            kind: .transferIn,
            amountMinor: 775,
            account: usd,
            occurredAt: base.addingTimeInterval(7_200)
        )
        inbound.externalRef = "MPESA-REF"
        try context.save()

        let candidates = try transfers.linkCandidates(for: out)
        #expect(candidates.count == 1)
        #expect(candidates.first?.entry.id == inbound.id)
        #expect(candidates.first?.reason == .reference)
        #expect(candidates.first?.timeDifference == 7_200)

        let reverse = try transfers.linkCandidates(for: inbound)
        #expect(reverse.map(\.id) == [out.id])
        #expect(reverse.first?.reason == .reference)
    }

    @Test("An amount within 1% and 15 minutes is a candidate")
    func amountAndTimeCandidate() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(
            kind: .transferOut, amountMinor: 100_000, feeMinor: 500, account: bank, occurredAt: base)
        let inbound = try ledger.record(
            kind: .transferIn,
            amountMinor: 100_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(10 * 60)
        )
        try context.save()

        let candidates = try transfers.linkCandidates(for: out)
        #expect(candidates.count == 1)
        #expect(candidates.first?.entry.id == inbound.id)
        #expect(candidates.first?.reason == .amountAndTime)
        #expect(candidates.first?.timeDifference == 600)
    }

    @Test("An amount outside 1% is not a candidate")
    func amountOutsideTolerance() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        _ = try ledger.record(
            kind: .transferIn,
            amountMinor: 98_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(5 * 60)
        )
        try context.save()

        #expect(try transfers.linkCandidates(for: out).isEmpty)
    }

    @Test("Sixteen minutes apart is not a candidate without a reference")
    func timeOutsideWindow() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        _ = try ledger.record(
            kind: .transferIn,
            amountMinor: 100_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(16 * 60)
        )
        try context.save()

        #expect(try transfers.linkCandidates(for: out).isEmpty)
    }

    @Test("Both legs must belong to different accounts")
    func candidateSameAccountRejected() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        _ = try ledger.record(
            kind: .transferIn,
            amountMinor: 100_000,
            account: bank,
            occurredAt: base.addingTimeInterval(60)
        )
        try context.save()

        #expect(try transfers.linkCandidates(for: out).isEmpty)
    }

    @Test("A same-direction leg is never a candidate")
    func candidateSameDirectionRejected() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        _ = try ledger.record(
            kind: .transferOut,
            amountMinor: 100_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(60)
        )
        try context.save()

        #expect(try transfers.linkCandidates(for: out).isEmpty)
    }

    @Test("A linked leg is not offered as a candidate")
    func candidateAlreadyLinkedExcluded() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let linkedOut = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        let linkedIn = try ledger.record(kind: .transferIn, amountMinor: 100_000, account: mobile, occurredAt: base)
        _ = try transfers.link(outLeg: linkedOut, inLeg: linkedIn)

        let unpairedOut = try ledger.record(
            kind: .transferOut,
            amountMinor: 100_000,
            account: bank,
            occurredAt: base.addingTimeInterval(60)
        )
        try context.save()

        #expect(try transfers.linkCandidates(for: unpairedOut).isEmpty)
    }

    @Test("Reference candidates sort before amount-and-time candidates")
    func candidatesReferenceFirst() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let wallet = try accounts.create(name: "Wallet", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        out.counterpartRef = "REF-9"

        let timed = try ledger.record(
            kind: .transferIn,
            amountMinor: 100_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(60)
        )
        let referenced = try ledger.record(
            kind: .transferIn,
            amountMinor: 250_000,
            account: wallet,
            occurredAt: base.addingTimeInterval(5 * 60)
        )
        referenced.externalRef = "REF-9"
        try context.save()

        let candidates = try transfers.linkCandidates(for: out)
        #expect(candidates.map(\.id) == [referenced.id, timed.id])
        #expect(candidates.first?.reason == .reference)
    }

    @Test("Linking without a reference rejects legs more than 15 minutes apart")
    func linkRejectsTimeMismatch() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        let inbound = try ledger.record(
            kind: .transferIn,
            amountMinor: 100_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(16 * 60)
        )
        try context.save()

        #expect(throws: TransferError.timeMismatch) {
            try transfers.link(outLeg: out, inLeg: inbound)
        }
    }

    @Test("A reference lets a delayed pair link")
    func linkAllowsReferenceAcrossTime() throws {
        let (accounts, transfers, context) = try makeServices()
        let ledger = LedgerService(context: context)
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        let out = try ledger.record(kind: .transferOut, amountMinor: 100_000, account: bank, occurredAt: base)
        out.counterpartRef = "REF-7"
        let inbound = try ledger.record(
            kind: .transferIn,
            amountMinor: 100_000,
            account: mobile,
            occurredAt: base.addingTimeInterval(3 * 60 * 60)
        )
        inbound.externalRef = "REF-7"
        try context.save()

        let transfer = try transfers.link(outLeg: out, inLeg: inbound)
        #expect(out.transfer?.id == transfer.id)
        #expect(inbound.transfer?.id == transfer.id)
    }
}
