//
//  MoneyMarketFormView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for adding a money market account with daily compounding.
public struct MoneyMarketFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppService.self) private var appService
    @Environment(AccountService.self) private var accountService
    @Environment(InvestmentService.self) private var investmentService

    @Bindable private var state: InvestmentFormState
    @State private var errorMessage: String?

    public init() {
        _state = Bindable(InvestmentFormState(mode: .moneyMarket))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Principal") {
                        HStack(spacing: ManotiSpacing.small) {
                            Text(state.currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("0.00", text: $state.principalText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    if let message = amountMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else {
                        Text("Interest compounds daily at the after-tax annual rate.")
                    }
                }

                Section {
                    LabeledContent("Annual rate") {
                        HStack(spacing: ManotiSpacing.small) {
                            TextField("10", text: $state.annualRateText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()

                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }

                    DatePicker("Started", selection: $state.startDate, displayedComponents: .date)

                    LabeledContent("Withholding tax") {
                        HStack(spacing: ManotiSpacing.small) {
                            TextField("10", text: $state.withholdingTaxText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()

                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Tax exempt", isOn: $state.taxExempt)
                } footer: {
                    if state.withholdingTaxBasisPoints == nil {
                        Text("Enter a withholding tax between 0% and 100%.")
                            .foregroundStyle(.red)
                    } else if !state.annualRateText.isEmpty && state.annualRateBasisPoints == nil {
                        Text("Enter a valid annual rate.")
                            .foregroundStyle(.red)
                    }
                }

                if let oneYearValue {
                    Section("After one year") {
                        LabeledContent("Projected value") {
                            AmountText(oneYearValue, style: .subheadline.weight(.semibold))
                        }
                    }
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
                } footer: {
                    if state.activeAccounts.isEmpty {
                        Text("The investment is recorded without a linked cash account.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $state.note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Money market")
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
                state.withholdingTaxText = "\(Decimal(appService.withholdingTaxBasisPoints) / 100)"
            }
        }
    }

    private var amountMessage: String? {
        if state.principalText.isEmpty {
            return nil
        }

        guard let principal = state.parsedPrincipal?.minorUnits else {
            return "Enter a valid principal amount."
        }

        return principal > 0 ? nil : "Enter a principal greater than zero."
    }

    private var oneYearValue: Money? {
        guard let principal = state.parsedPrincipal,
            let rate = state.annualRateBasisPoints,
            let tax = state.withholdingTaxBasisPoints
        else {
            return nil
        }

        let value = InvestmentMath.moneyMarketValueMinor(
            principalMinor: principal.minorUnits,
            annualRateBasisPoints: rate,
            withholdingTaxBasisPoints: tax,
            taxExempt: state.taxExempt,
            days: 365
        )
        return Money(minorUnits: value, currency: principal.currency)
    }

    private func save() {
        do {
            try state.save(investmentService: investmentService)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
