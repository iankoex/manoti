//
//  AddEntryFigureBridgeTests.swift
//  ManotiTests
//

import Testing

@testable import AppModels
@testable import EntryFormFeature
@testable import QuickAddFeature
@testable import TransfersFeature

@MainActor
@Suite("Add entry figures")
struct AddEntryFigureBridgeTests {
    @Test("Amount and fee carry from expense or income into transfer")
    func entryToTransfer() {
        let entry = EntryFormState()
        entry.amountText = "2500"
        entry.feeText = "50"
        entry.activeField = .fee

        let transfer = TransferFormState()
        AddEntryFigureBridge.carry(from: entry, to: transfer)

        #expect(transfer.amountText == "2500")
        #expect(transfer.feeText == "50")
        #expect(transfer.activeField == .fee)
    }

    @Test("Amount and fee carry back from transfer")
    func transferToEntry() {
        let transfer = TransferFormState()
        transfer.amountText = "1200"
        transfer.feeText = "30"
        transfer.activeField = .fee

        let entry = EntryFormState()
        AddEntryFigureBridge.carry(from: transfer, to: entry)

        #expect(entry.amountText == "1200")
        #expect(entry.feeText == "30")
        #expect(entry.activeField == .fee)
    }

    @Test("Returning from the received field falls back to editing the amount")
    func receivedFallsBackToAmount() {
        let transfer = TransferFormState()
        transfer.amountText = "10"
        transfer.feeText = "2"
        transfer.activeField = .received

        let entry = EntryFormState()
        AddEntryFigureBridge.carry(from: transfer, to: entry)

        #expect(entry.amountText == "10")
        #expect(entry.feeText == "2")
        #expect(entry.activeField == .amount)
    }
}
