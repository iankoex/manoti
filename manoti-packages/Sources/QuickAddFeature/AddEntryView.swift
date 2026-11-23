//
//  AddEntryView.swift
//  QuickAddFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import SwiftUI
import TransfersFeature

public enum AddEntryMode: String, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    public var id: String { rawValue }

    public var title: String {
        switch self {
            case .expense: "Expense"
            case .income: "Income"
            case .transfer: "Transfer"
        }
    }

    public var ledgerKind: LedgerEntryKind {
        switch self {
            case .expense: .expense
            case .income: .income
            case .transfer: .transferOut
        }
    }
}

/// One sheet for money in, money out and money moved between accounts.
public struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(CategoryService.self) private var categoryService
    @Environment(LedgerService.self) private var ledgerService
    @Environment(TransferService.self) private var transferService
    @AppStorage("manoti.lastAccountID") private var lastAccountID = ""

    @State private var mode: AddEntryMode = .expense
    @State private var entryState = EntryFormState()
    @State private var transferState = TransferFormState()
    @State private var errorMessage: String?

    public init(startingMode: AddEntryMode = .expense) {
        _mode = State(initialValue: startingMode)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $mode) {
                    ForEach(AddEntryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                form
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                }
            }
            .alert(
                "Could not save",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                reload()
            }
            .onChange(of: mode) { oldMode, newMode in
                entryState.setKind(newMode.ledgerKind)

                if newMode == .transfer, oldMode != .transfer {
                    AddEntryFigureBridge.carry(from: entryState, to: transferState)
                    transferState.selectDefaults()
                } else if oldMode == .transfer, newMode != .transfer {
                    AddEntryFigureBridge.carry(from: transferState, to: entryState)
                }
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        switch mode {
            case .expense, .income:
                EntryFormView(state: entryState)
            case .transfer:
                TransferFormView(state: transferState)
        }
    }

    private var canSave: Bool {
        mode == .transfer ? transferState.canSave : entryState.canSave
    }

    private func reload() {
        entryState.reload(accountService: accountService, categoryService: categoryService)
        entryState.selectDefaultAccount(lastAccountID: lastAccountID)
        entryState.setKind(mode.ledgerKind)
        transferState.reload(accountService: accountService)
        transferState.selectDefaults()
    }

    private func save() {
        do {
            switch mode {
                case .expense, .income:
                    try entryState.save(ledger: ledgerService)

                    if let accountID = entryState.selectedAccount?.id {
                        lastAccountID = accountID.uuidString
                    }
                case .transfer:
                    try transferState.save(transferService: transferService)
            }

            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
            case EntryFormError.missingAccount:
                "Add an account before recording this."
            case EntryFormError.invalidAmount:
                "Enter an amount greater than zero."
            case TransferError.sameAccount:
                "Choose two different accounts."
            case TransferError.invalidAmount:
                "Enter an amount greater than zero."
            case TransferError.amountInRequired:
                "Enter the amount the receiving account gets."
            case TransferError.amountMismatch:
                "For the same currency, the amounts must match."
            case TransferError.archivedAccount:
                "One of these accounts is archived."
            default:
                error.localizedDescription
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func navigationBarTitleDisplayModeInlineCompat() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// Keeps the amount and fee entered in one mode when the user switches tabs.
@MainActor
enum AddEntryFigureBridge {
    static func carry(from entry: EntryFormState, to transfer: TransferFormState) {
        transfer.amountText = entry.amountText
        transfer.feeText = entry.feeText
        transfer.activeField = entry.activeField == .fee ? .fee : .amount
    }

    static func carry(from transfer: TransferFormState, to entry: EntryFormState) {
        entry.amountText = transfer.amountText
        entry.feeText = transfer.feeText
        entry.activeField = transfer.activeField == .fee ? .fee : .amount
    }
}
