//
//  ReceiptRuleTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("Paybill receipt rules")
struct ReceiptRuleTests {
    private let paybill =
        "UKP6H2TUYY Confirmed. Ksh280.00 sent to Family Bank Pesa Pap for account 2829646 on 25/11/26 at 5:58 PM New M-PESA balance is Ksh260.68. Transaction cost, Ksh5.00.Amount you can transact within the day is 497,486.00. See all your balances now https://saf.cx/kWQpy"
    private let receipt =
        "Confirmed. Payment of Ksh. 280.00 to TABISCARE PHARMACY(2829646) has been received. Ref: UKP6H2TUYY on 25-11-2026 17:58Hrs."
    private let bankOut =
        "Bank to M-PESA transfer of KES 2,000.00 to 254700000000 - IAN KIPRONO successfully processed. Transaction Ref ID: 5989CBLR1498. M-PESA Ref ID: UKP6H2R80I."

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()

        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        _ = try? SharedRulesService(context: context, defaults: defaults)
            .installBundledRulesIfNeeded()
        return context
    }

    private func parse(_ text: String, sender: String?, in context: ModelContext) throws -> ParsedMessage {
        let outcome = try ParserService(context: context).parse(
            text: text,
            sender: sender,
            receivedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        guard case .parsed(let message) = outcome else {
            Issue.record("The message was not recognised")
            throw ParseFailure.unrecognised
        }

        return message
    }

    private enum ParseFailure: Error {
        case unrecognised
    }

    @Test("The M-Pesa paybill message is a transaction with its fee and balance")
    func paybillMessage() throws {
        let context = try makeContext()
        let message = try parse(paybill, sender: "M-PESA", in: context)

        #expect(message.role == .transaction)
        #expect(message.messageType == .expense)
        #expect(message.amountMinor == 28_000)
        #expect(message.feeMinor == 500)
        #expect(message.balanceAfterMinor == 26_068)
        #expect(message.payee == "Family Bank Pesa Pap")
        #expect(message.reference == "UKP6H2TUYY")
    }

    @Test("The bank receipt is a confirmation naming the merchant")
    func bankReceipt() throws {
        let context = try makeContext()
        let message = try parse(receipt, sender: "FAMILY BANK", in: context)

        #expect(message.role == .confirmation)
        #expect(message.amountMinor == 28_000)
        #expect(message.payee == "TABISCARE PHARMACY")
        #expect(message.reference == "UKP6H2TUYY")
        #expect(message.accountHint == "2829646")

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: message.occurredAt
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 25)
        #expect(parts.hour == 17)
        #expect(parts.minute == 58)
    }

    @Test("The bank transfer message captures the destination phone")
    func bankTransferPhone() throws {
        let context = try makeContext()
        let message = try parse(bankOut, sender: "IM BANK", in: context)

        #expect(message.role == .transaction)
        #expect(message.messageType == .transferOut)
        #expect(message.reference == "5989CBLR1498")
        #expect(message.counterpartReference == "UKP6H2R80I")
        #expect(message.accountHint == "254700000000")
    }

    @Test("A rule without a role is a transaction")
    func defaultRole() {
        let rule = ParseRule(
            name: "Plain",
            messageType: .expense,
            pattern: "X (?<amount>KES [0-9]+)"
        )

        #expect(rule.role == .transaction)
    }
}
