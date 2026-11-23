//
//  TransferFormStateTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import TransfersFeature

@MainActor
@Suite("Transfer form")
struct TransferFormStateTests {
    private struct Fixtures {
        let state: TransferFormState
        let accounts: AccountService
        let transfers: TransferService
        let context: ModelContext
    }

    private func makeFixtures() throws -> Fixtures {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let accounts = AccountService(context: context)
        let transfers = TransferService(context: context)
        let state = TransferFormState()
        state.reload(accountService: accounts)
        return Fixtures(state: state, accounts: accounts, transfers: transfers, context: context)
    }

    @Test("The keypad edits the amount, fee and received fields separately")
    func keypadTargets() throws {
        let fixtures = try makeFixtures()
        let kes = try fixtures.accounts.create(name: "KES", kind: .bank, currencyCode: "KES")
        let usd = try fixtures.accounts.create(name: "USD", kind: .bank, currencyCode: "USD")
        fixtures.state.reload(accountService: fixtures.accounts)
        fixtures.state.fromID = kes.id
        fixtures.state.toID = usd.id

        fixtures.state.activeField = .amount
        for key in ["1", "0", "0"] {
            fixtures.state.press(key)
        }

        fixtures.state.activeField = .fee
        fixtures.state.press("5")

        fixtures.state.activeField = .received
        fixtures.state.press("7")

        #expect(fixtures.state.amountText == "100")
        #expect(fixtures.state.feeText == "5")
        #expect(fixtures.state.receivedText == "7")
    }

    @Test("Received is ignored when both accounts use the same currency")
    func receivedIgnoredForSameCurrency() throws {
        let fixtures = try makeFixtures()
        let kes = try fixtures.accounts.create(name: "KES", kind: .bank, currencyCode: "KES")
        let mpesa = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        fixtures.state.reload(accountService: fixtures.accounts)
        fixtures.state.fromID = kes.id
        fixtures.state.toID = mpesa.id

        fixtures.state.activeField = .received
        fixtures.state.press("9")

        #expect(fixtures.state.receivedText.isEmpty)
    }

    @Test("A non-numeric fee blocks saving")
    func invalidFee() throws {
        let fixtures = try makeFixtures()
        let bank = try fixtures.accounts.create(name: "Bank", kind: .bank, openingBalanceMinor: 200_000)
        let mpesa = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        fixtures.state.reload(accountService: fixtures.accounts)
        fixtures.state.fromID = bank.id
        fixtures.state.toID = mpesa.id
        fixtures.state.amountText = "1000"
        fixtures.state.feeText = "abc"

        #expect(!fixtures.state.canSave)
        #expect(throws: TransferError.invalidAmount) {
            try fixtures.state.save(transferService: fixtures.transfers)
        }
    }

    @Test("Changing an account clears a stale received amount")
    func clearsReceived() throws {
        let fixtures = try makeFixtures()
        let kes = try fixtures.accounts.create(name: "KES", kind: .bank, currencyCode: "KES")
        let usd = try fixtures.accounts.create(name: "USD", kind: .bank, currencyCode: "USD")
        let otherUsd = try fixtures.accounts.create(name: "Other USD", kind: .bank, currencyCode: "USD")
        fixtures.state.reload(accountService: fixtures.accounts)
        fixtures.state.fromID = kes.id
        fixtures.state.toID = usd.id
        fixtures.state.receivedText = "999"

        fixtures.state.toID = otherUsd.id
        #expect(fixtures.state.receivedText.isEmpty)
    }

    @Test("Saving uses the date chosen in the form")
    func saveUsesDate() throws {
        let fixtures = try makeFixtures()
        let bank = try fixtures.accounts.create(name: "Bank", kind: .bank, openingBalanceMinor: 200_000)
        let mpesa = try fixtures.accounts.create(name: "M-Pesa", kind: .mobileMoney)
        fixtures.state.reload(accountService: fixtures.accounts)
        fixtures.state.fromID = bank.id
        fixtures.state.toID = mpesa.id
        fixtures.state.amountText = "1000"
        fixtures.state.feeText = "20"

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        fixtures.state.occurredAt = date

        try fixtures.state.save(transferService: fixtures.transfers)

        let transfer = try #require(try fixtures.context.fetch(FetchDescriptor<Transfer>()).first)
        #expect(transfer.occurredAt == date)
        #expect(transfer.outTransaction?.feeMinor == 2_000)
        #expect(transfer.inTransaction?.amountMinor == 100_000)
    }
}
