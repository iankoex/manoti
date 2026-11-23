//
//  ParserTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Message parser")
struct ParserTests {
    private let receivedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeParser() throws -> ParserService {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return ParserService(context: context)
    }

    private func parsed(_ text: String, sender: String) throws -> ParsedMessage {
        let parser = try makeParser()
        let outcome = try parser.parse(text: text, sender: sender, receivedAt: receivedAt)

        guard case .parsed(let message) = outcome else {
            Issue.record("Message was not recognised: \(text)")
            throw TestFailure()
        }

        return message
    }

    private struct TestFailure: Error {}

    @Test("Seeding creates two rule sets and seven rules")
    func seedRules() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()

        let sets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let rules = try context.fetch(FetchDescriptor<ParseRule>())

        #expect(sets.count == 2)
        #expect(rules.count == 7)
        #expect(sets.contains { $0.seedKey == "mpesa" })
        #expect(sets.contains { $0.seedKey == "im-bank" })
    }

    @Test("M-Pesa paid parses amount, fee, payee, reference and date")
    func mpesaPaid() throws {
        let message = try parsed(
            "UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Nixomb Limited - Shell Bellevue. on 21/11/26 at 11:54 AM.New M-PESA balance is Ksh939.68. Transaction cost, Ksh8.30. Amount you can transact within the day is 498,490.00. See all your balances now https://saf.cx/kWQpy",
            sender: "M-PESA"
        )

        #expect(message.messageType == .expense)
        #expect(message.amountMinor == 151_000)
        #expect(message.feeMinor == 830)
        #expect(message.payee == "Nixomb Limited - Shell Bellevue")
        #expect(message.reference == "UKL6H2AF65")
        #expect(message.balanceAfterMinor == 93_968)
        #expect(message.dateFromMessage)
        #expect(message.confidence >= 0.85)

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: message.occurredAt
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 21)
        #expect(parts.hour == 11)
        #expect(parts.minute == 54)
    }

    @Test("M-Pesa received is income with no fee")
    func mpesaReceived() throws {
        let message = try parsed(
            "UKJME2X5ZR Confirmed.You have received Ksh100.00 from BRENDAH  MBINYA 0746***702 on 19/11/26 at 3:07 PM  New M-PESA balance is Ksh1,744.98. Invest & earn daily interest with ZIIDI on https://saf.cx/cF6ir",
            sender: "M-PESA"
        )

        #expect(message.messageType == .income)
        #expect(message.amountMinor == 10_000)
        #expect(message.feeMinor == 0)
        #expect(message.reference == "UKJME2X5ZR")
        #expect(message.payee.contains("BRENDAH"))
    }

    @Test("A bank top-up into M-Pesa is a transfer leg")
    func bankToMpesaIn() throws {
        let message = try parsed(
            "UKL6H2A7R0 Confirmed. You have received Ksh2,000.00 from IM BANK LIMITED- APP on 21/11/26 at 11:36 AM. New M-PESA balance is Ksh2,457.98. Buy goods with M-PESA.",
            sender: "M-PESA"
        )

        #expect(message.messageType == .transferIn)
        #expect(message.amountMinor == 200_000)
        #expect(message.payee == "IM BANK LIMITED- APP")
    }

    @Test("Bank to M-Pesa transfer carries the counterpart reference")
    func bankTransferOut() throws {
        let message = try parsed(
            "Bank to M-PESA transfer of KES 600.00 to 254700000000 - IAN KIPRONO successfully processed. Transaction Ref ID: 5951WTXH3777. M-PESA Ref ID: UKK6H292PF.",
            sender: "IM BANK"
        )

        #expect(message.messageType == .transferOut)
        #expect(message.amountMinor == 60_000)
        #expect(message.payee == "254700000000 - IAN KIPRONO")
        #expect(message.reference == "5951WTXH3777")
        #expect(message.counterpartReference == "UKK6H292PF")
        #expect(!message.dateFromMessage)
        #expect(message.occurredAt == receivedAt)
    }

    @Test("PesaLink income parses without a message date")
    func pesalink() throws {
        let message = try parsed(
            "Dear Customer,You have received KES 5000 via PesaLink into Acc 01234567890123 Tran Ref 000300572026112108351801173354. For enquiry,call 020 3221000. IM Bank.",
            sender: "IM BANK"
        )

        #expect(message.messageType == .income)
        #expect(message.amountMinor == 500_000)
        #expect(message.accountHint == "01234567890123")
        #expect(message.reference == "000300572026112108351801173354")
        #expect(!message.dateFromMessage)
    }

    @Test("A card purchase parses the ISO timestamp and card last four")
    func cardPurchase() throws {
        let message = try parsed(
            "Dear IAN, You made a purchase ofKES 766.00 on 2026-11-19 17:42:06 at QUICK MART LIMITED using I&M 5477********7653. If you did not effect the transaction, urgently contact us on 0719088000 or Toll Free 0800721088",
            sender: "IM BANK"
        )

        #expect(message.messageType == .expense)
        #expect(message.amountMinor == 76_600)
        #expect(message.payee == "QUICK MART LIMITED")
        #expect(message.cardLast4 == "7653")

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: message.occurredAt
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 19)
        #expect(parts.hour == 17)
        #expect(parts.minute == 42)
        #expect(parts.second == 6)
    }

    @Test("A card purchase without a timestamp falls back to the received time")
    func cardPurchaseUndated() throws {
        let message = try parsed(
            "Dear IAN, You made a purchase of KES 766.00 at QUICK MART LIMITED using I&M 5477********7653. If you did not effect the transaction, urgently contact us on 0719088000.",
            sender: "IM BANK"
        )

        #expect(message.messageType == .expense)
        #expect(message.amountMinor == 76_600)
        #expect(message.payee == "QUICK MART LIMITED")
        #expect(!message.dateFromMessage)
        #expect(message.occurredAt == receivedAt)
    }

    @Test("An own-account transfer is never an expense")
    func ownTransfer() throws {
        let message = try parsed(
            "Transfer to Own Account of KES 16,700.00 to IAN KIPRONO A/c 7890123 on 19/11/2026 12:29 processed successfully. Transaction Ref ID: 431567921248.",
            sender: "IM BANK"
        )

        #expect(message.messageType == .transferOut)
        #expect(message.amountMinor == 1_670_000)
        #expect(message.accountHint == "7890123")
        #expect(message.reference == "431567921248")
    }

    @Test("An own-account transfer without a date uses the received time")
    func ownTransferUndated() throws {
        let message = try parsed(
            "Transfer to Own Account of KES 16,700.00 to IAN KIPRONO A/c 7890123 processed successfully. Transaction Ref ID: 431567921248.",
            sender: "IM BANK"
        )

        #expect(message.messageType == .transferOut)
        #expect(message.payee == "IAN KIPRONO")
        #expect(!message.dateFromMessage)
        #expect(message.occurredAt == receivedAt)
    }

    @Test("Unrelated text is unrecognised")
    func unrecognised() throws {
        let parser = try makeParser()

        guard case .unrecognised = try parser.parse(text: "Hello there", sender: "M-PESA", receivedAt: receivedAt)
        else {
            Issue.record("Expected unrecognised outcome")
            return
        }
    }

    @Test("An unknown sender still uses every rule set")
    func unknownSender() throws {
        let parser = try makeParser()
        let text =
            "UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Petrol Station. on 21/11/26 at 11:54 AM."
            + " New mobile money balance is Ksh939.68. Transaction cost, Ksh8.30."

        for sender in [nil, "SANTANDER"] as [String?] {
            let outcome = try parser.parse(text: text, sender: sender, receivedAt: receivedAt)

            guard case .parsed(let message) = outcome else {
                Issue.record("A message from an unknown sender should still parse: \(sender ?? "nil")")
                return
            }

            #expect(message.messageType == .expense)
            #expect(message.amountMinor == 151_000)
        }
    }

    @Test("A message without a date falls back to the received time")
    func undatedFallback() {
        let result = DateExtractor.extract(date: nil, time: nil, ampm: nil, fallback: receivedAt)

        #expect(result.date == receivedAt)
        #expect(!result.fromMessage)
    }

    @Test("A truncated amount does not produce a wrong number")
    func truncated() throws {
        let parser = try makeParser()
        let outcome = try parser.parse(
            text: "UKL6H2AF65 Confirmed. Ksh paid to Shell.",
            sender: "M-PESA",
            receivedAt: receivedAt
        )

        guard case .unrecognised = outcome else {
            Issue.record("Truncated message should not parse")
            return
        }
    }
}
