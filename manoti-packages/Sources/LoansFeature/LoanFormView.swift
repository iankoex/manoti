//
//  LoanFormView.swift
//  LoansFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for creating a loan. Presents its own navigation stack and Save/Cancel bar.
public struct LoanFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(LoanService.self) private var loanService

    @Bindable private var state: LoanFormState
    @State private var errorMessage: String?

    public init(direction: LoanDirection) {
        _state = Bindable(LoanFormState(direction: direction))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: $state.direction) {
                        ForEach(LoanDirection.allCases) { direction in
                            Text(direction.displayName).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(
                        state.direction == .lent
                            ? "Money leaves the account now and comes back as it is repaid."
                            : "Money enters the account now and is repaid later."
                    )
                }

                Section("Counterparty") {
                    TextField("Who is the loan with?", text: $state.counterparty)

                    if !state.counterparty.isEmpty && state.trimmedCounterparty.isEmpty {
                        Text("Enter a name.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Amount") {
                    LabeledContent("Amount") {
                        HStack(spacing: ManotiSpacing.small) {
                            Text(state.selectedAccount?.currency.code ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("0.00", text: $state.amountText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }

                    amountFooter
                }

                Section {
                    Picker("Account", selection: $state.selectedAccountID) {
                        if state.activeAccounts.isEmpty {
                            Text("No active accounts").tag(UUID?.none)
                        } else {
                            ForEach(state.activeAccounts) { account in
                                Text("\(account.displayName) · \(account.currency.code)")
                                    .tag(Optional(account.id))
                            }
                        }
                    }

                    DatePicker("Started", selection: $state.startedAt, displayedComponents: .date)

                    Toggle("Due date", isOn: dueDateToggle)

                    if state.dueAt != nil {
                        DatePicker("Due", selection: dueDateBinding, displayedComponents: .date)
                    }
                } footer: {
                    if state.activeAccounts.isEmpty {
                        Text("Add an active account before recording a loan.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $state.note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(state.direction == .lent ? "Lend money" : "Borrow money")
            .navigationBarTitleDisplayModeInlineCompact()
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
            .task {
                state.reload(accountService: accountService)
            }
        }
    }

    @ViewBuilder
    private var amountFooter: some View {
        if state.selectedAccount == nil {
            EmptyView()
        } else if !state.amountText.isEmpty,
            let parsed = state.parsedAmount,
            parsed.minorUnits == 0
        {
            Text("Enter an amount greater than zero.")
                .font(.caption)
                .foregroundStyle(.red)
        } else if !state.amountText.isEmpty && state.parsedAmount == nil {
            Text("Enter a valid amount.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var dueDateToggle: Binding<Bool> {
        Binding(
            get: { state.dueAt != nil },
            set: { isOn in
                if isOn {
                    let fallback =
                        Calendar.current.date(byAdding: .month, value: 1, to: state.startedAt)
                        ?? state.startedAt
                    state.dueAt = max(fallback, state.startedAt)
                } else {
                    state.dueAt = nil
                }
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { state.dueAt ?? state.startedAt },
            set: { state.dueAt = $0 }
        )
    }

    private func save() {
        do {
            try state.save(loanService: loanService)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func navigationBarTitleDisplayModeInlineCompact() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
