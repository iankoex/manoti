//
//  TransferFormView.swift
//  TransfersFeature
//

import AppModels
import Modifiers
import SwiftUI

/// Transfer form laid out like the expense and income forms: amount first, account chips,
/// then an optional details section and the shared custom keypad.
public struct TransferFormView: View {
    @Bindable private var state: TransferFormState
    @Environment(\.manotiAmountsHidden) private var amountsHidden
    @FocusState private var noteFocused: Bool

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
            .padding(.bottom, noteFocused ? 20 : 280)
        }
        .safeAreaInset(edge: .bottom) {
            if !noteFocused {
                AmountKeypad { state.press($0) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: state.fromID) { _, _ in
            if state.toID == state.fromID {
                state.toID = state.availableTargets.first?.id
            }
        }
        .onChange(of: state.requiresConvertedAmount) { _, needsAmount in
            if !needsAmount, state.activeField == .received {
                state.activeField = .amount
            }
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                noteFocused = false
                state.activeField = .amount
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.fromAccount?.currency.code ?? CurrencyCatalog.defaultCurrency.code)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(state.amountText.isEmpty ? "0" : state.amountText)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Amount, \(state.amountText.isEmpty ? "0" : state.amountText)")

            VStack(alignment: .trailing, spacing: 8) {
                AmountFieldChip(
                    title: "Fee",
                    value: state.feeText,
                    isActive: state.activeField == .fee
                ) {
                    noteFocused = false
                    state.activeField = .fee
                }

                if state.requiresConvertedAmount {
                    AmountFieldChip(
                        title: "Received",
                        value: state.receivedText,
                        currencyCode: state.toAccount?.currency.code,
                        isActive: state.activeField == .received
                    ) {
                        noteFocused = false
                        state.activeField = .received
                    }
                }
            }
        }
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
                    .focused($noteFocused)
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
