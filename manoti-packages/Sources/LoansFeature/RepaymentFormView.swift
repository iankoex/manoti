//
//  RepaymentFormView.swift
//  LoansFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for recording a repayment. Rejects overpayments inline before saving.
public struct RepaymentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(LoanService.self) private var loanService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @Bindable private var state: RepaymentFormState
    @State private var errorMessage: String?

    public init(loan: Loan) {
        _state = Bindable(RepaymentFormState(loan: loan))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Outstanding") {
                        AmountText(state.outstanding, style: .body.weight(.semibold))
                    }
                }

                Section("Amount") {
                    LabeledContent("Repayment") {
                        HStack(spacing: ManotiSpacing.small) {
                            Text(state.loan.currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("0.00", text: $state.amountText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }

                    if let message = state.validationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let remaining = state.remainingPreview {
                        LabeledContent("Remaining after") {
                            Text(AmountMask.money(remaining, hidden: amountsHidden))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("From") {
                    Picker("Account", selection: $state.selectedAccountID) {
                        if state.eligibleAccounts.isEmpty {
                            Text("No \(state.loan.currency.code) accounts").tag(UUID?.none)
                        } else {
                            ForEach(state.eligibleAccounts) { account in
                                Text("\(account.displayName) · \(account.currency.code)")
                                    .tag(Optional(account.id))
                            }
                        }
                    }

                    DatePicker("Date", selection: $state.occurredAt, displayedComponents: .date)

                    TextField("Optional note", text: $state.note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add repayment")
            .navigationBarTitleDisplayModeInlineCompatRepayment()
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
    fileprivate func navigationBarTitleDisplayModeInlineCompatRepayment() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
