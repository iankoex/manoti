//
//  EntryFormView.swift
//  QuickAddFeature
//

import AppModels
import Modifiers
import SwiftUI

/// Expense/income form: keypad first, then account and category chips.
public struct EntryFormView: View {
    @Bindable private var state: EntryFormState
    @FocusState private var noteFocused: Bool

    public init(state: EntryFormState) {
        _state = Bindable(state)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                amountDisplay
                accountPicker
                categoryPicker
                detailsSection
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
    }

    private var amountDisplay: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                noteFocused = false
                state.activeField = .amount
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.selectedAccount?.currency.code ?? CurrencyCatalog.defaultCurrency.code)
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

            AmountFieldChip(
                title: "Fee",
                value: state.feeText,
                isActive: state.activeField == .fee
            ) {
                noteFocused = false
                state.activeField = .fee
            }
        }
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if state.activeAccounts.isEmpty {
                Text("Add an account first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.activeAccounts) { account in
                            AccountChip(account: account, isSelected: state.selectedAccountID == account.id)
                                .onTapGesture { state.selectedAccountID = account.id }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var categoryPicker: some View {
        CategoryDrillDownPicker(
            groups: state.visibleGroups,
            kind: state.kind.categoryKind,
            selectedCategoryID: $state.selectedCategoryID,
            selectedCategory: state.selectedCategory
        )
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
}
