//
//  LedgerEntryEditorView.swift
//  LedgerFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for editing one manually recorded ledger entry.
public struct LedgerEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerService.self) private var ledgerService

    @Bindable private var state: LedgerEntryEditorState
    @State private var errorMessage: String?

    public init(entry: LedgerEntry, accounts: [Account], categories: [SpendingCategory]) {
        _state = Bindable(LedgerEntryEditorState(entry: entry, accounts: accounts, categories: categories))
    }

    public var body: some View {
        NavigationStack {
            Form {
                if state.isLinkedEntry {
                    linkedNotice
                } else {
                    kindSection
                    amountSection
                    dateSection
                    accountSection
                    categorySection
                    detailsSection
                }
            }
            .navigationTitle("Edit entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!state.canSave)
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
        }
    }

    private var linkedNotice: some View {
        Section {
            Label {
                Text("This entry belongs to a transfer, loan or investment. Change it from its own screen.")
            } icon: {
                Image(systemName: "link")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var kindSection: some View {
        Section {
            if state.isKindEditable {
                Picker("Type", selection: $state.kind) {
                    ForEach(state.kindOptions) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            } else {
                LabeledContent("Type") {
                    Text(state.kind.displayName)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if !state.isKindEditable {
                Text("The kind is fixed for this entry.")
            }
        }
    }

    private var amountSection: some View {
        Section {
            LabeledContent("Amount") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.currency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $state.amountText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    if state.kind == .adjustment || state.kind == .openingBalance {
                        Button {
                            state.toggleAmountSign()
                        } label: {
                            Image(systemName: "plus.forwardslash.minus")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change amount sign")
                    }
                }
            }

            LabeledContent("Fee") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.currency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $state.feeText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                if let message = state.validationMessage, !state.amountText.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("A negative amount is only valid for adjustments and opening balances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker("Date", selection: $state.occurredAt)
        }
    }

    private var accountSection: some View {
        Section {
            if state.accounts.isEmpty {
                Text("No active accounts available.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Account", selection: $state.accountID) {
                    ForEach(state.accounts) { account in
                        Text(account.displayName).tag(Optional(account.id))
                    }
                }
            }
        } footer: {
            if state.accounts.isEmpty {
                Text("Unarchive or add an account before editing this entry.")
            }
        }
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $state.categoryID) {
                Text("None").tag(UUID?.none)

                ForEach(state.visibleCategories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Payee", text: $state.payee)

            TextField("Note", text: $state.note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private func save() {
        do {
            try state.save(using: ledgerService)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
