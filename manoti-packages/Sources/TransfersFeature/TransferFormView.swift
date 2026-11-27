//
//  TransferFormView.swift
//  TransfersFeature
//

import AppModels
import Modifiers
import SwiftUI

private enum TransferField: Hashable {
    case amount
    case fee
    case received
    case note
}

/// Transfer form laid out like the expense and income forms: amount first, account chips,
/// then an optional details section. The system numeric keyboard edits the field in focus.
public struct TransferFormView: View {
    @Bindable private var state: TransferFormState
    @Environment(\.manotiAmountsHidden) private var amountsHidden
    @FocusState private var focusedField: TransferField?

    public init(state: TransferFormState) {
        _state = Bindable(state)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                amountDisplay
                accountPicker(
                    title: "From",
                    accounts: state.activeAccounts,
                    selection: $state.fromID
                )
                accountPicker(
                    title: "To",
                    accounts: state.availableTargets,
                    selection: $state.toID
                )
                detailsSection

                if let preview = state.balancePreview {
                    balancePreview(preview)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            focusedField = .amount
        }
        .onChange(of: state.fromID) { _, _ in
            if state.toID == state.fromID {
                state.toID = state.availableTargets.first?.id
            }
        }
        .onChange(of: state.requiresConvertedAmount) { _, needsAmount in
            if !needsAmount, focusedField == .received {
                focusedField = .amount
            }
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.fromAccount?.currency.code ?? CurrencyCatalog.defaultCurrency.code)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("0", text: amountBinding)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .decimalKeyboard()
                    .focused($focusedField, equals: .amount)
                    .accessibilityLabel("Amount")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                compactField("Fee", text: feeBinding, field: .fee)

                if state.requiresConvertedAmount {
                    compactField("Received", text: receivedBinding, field: .received)
                }
            }
        }
    }

    private func compactField(
        _ title: String,
        text: Binding<String>,
        field: TransferField
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("0", text: text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 64, height: 22, alignment: .trailing)
                .padding(.trailing, 2)
                .decimalKeyboard()
                .focused($focusedField, equals: field)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.35), in: .capsule)
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { state.amountText },
            set: {
                state.amountText = AmountEntry.sanitisedText(
                    $0,
                    exponent: state.fromAccount?.currency.exponent
                        ?? CurrencyCatalog.defaultCurrency.exponent
                )
            }
        )
    }

    private var feeBinding: Binding<String> {
        Binding(
            get: { state.feeText },
            set: {
                state.feeText = AmountEntry.sanitisedText(
                    $0,
                    exponent: state.fromAccount?.currency.exponent
                        ?? CurrencyCatalog.defaultCurrency.exponent
                )
            }
        )
    }

    private var receivedBinding: Binding<String> {
        Binding(
            get: { state.receivedText },
            set: {
                state.receivedText = AmountEntry.sanitisedText(
                    $0,
                    exponent: state.toAccount?.currency.exponent
                        ?? CurrencyCatalog.defaultCurrency.exponent
                )
            }
        )
    }

    private func accountPicker(
        title: String,
        accounts: [Account],
        selection: Binding<UUID?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if accounts.isEmpty {
                Text(title == "To" ? "Add another account to transfer to." : "Add an account first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(accounts) { account in
                            AccountChip(account: account, isSelected: selection.wrappedValue == account.id)
                                .onTapGesture {
                                    selection.wrappedValue = account.id
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var detailsSection: some View {
        DisclosureGroup("Date and note", isExpanded: $state.showsDetails) {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Date", selection: $state.occurredAt)

                TextField("Note", text: $state.note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .note)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
    }

    private func balancePreview(_ rows: [(name: String, balance: Money)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("After this transfer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(rows, id: \.name) { row in
                HStack {
                    Text(row.name)
                        .font(.subheadline)

                    Spacer()

                    Text(AmountMask.money(row.balance, hidden: amountsHidden))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
    }
}
