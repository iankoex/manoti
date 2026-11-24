//
//  EntryFormView.swift
//  EntryFormFeature
//

import AppModels
import Modifiers
import SwiftUI

/// The shared money-entry form: keypad first, then account and category, then details.
///
/// Used by Add, Inbox review and Ledger edit. The caller supplies the navigation chrome
/// and, for review, a footer with the original message and the ignore action.
public struct EntryFormView: View {
    @Bindable private var state: EntryFormState
    private let showsKindControl: Bool
    private let footer: AnyView

    @FocusState private var noteFocused: Bool

    public init(state: EntryFormState, showsKindControl: Bool = false) {
        _state = Bindable(state)
        self.showsKindControl = showsKindControl
        self.footer = AnyView(EmptyView())
    }

    public init<Footer: View>(
        state: EntryFormState,
        showsKindControl: Bool = false,
        @ViewBuilder footer: () -> Footer
    ) {
        _state = Bindable(state)
        self.showsKindControl = showsKindControl
        self.footer = AnyView(footer())
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if state.isLinkedEntry {
                    linkedNotice
                } else {
                    if showsKindControl {
                        kindSection
                    }

                    amountDisplay
                    accountPicker

                    if let validationHint {
                        Text(validationHint)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if state.showsCategory {
                        categoryPicker
                    }

                    detailsSection
                    footer
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, noteFocused ? 20 : 300)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !noteFocused, !state.isLinkedEntry {
                AmountKeypad { state.press($0) }
            }
        }
    }

    /// Explains why the primary action is disabled. Hidden on Add until the user starts.
    private var validationHint: String? {
        guard !state.canSave else {
            return nil
        }

        if state.purpose == .create, state.amountText.isEmpty {
            return nil
        }

        return state.validationMessage
    }

    private var linkedNotice: some View {        Label {
            Text("This entry belongs to a transfer, loan or investment. Change it from its own screen.")
        } icon: {
            Image(systemName: "link")
        }
        .foregroundStyle(.secondary)
    }

    private var kindSection: some View {
        Group {
            if state.isKindEditable {
                Picker("Type", selection: $state.kind) {
                    ForEach(state.kindOptions) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                HStack {
                    Text("Type")
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    Text(state.kind.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                    Text(state.currency.code)
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

                if state.supportsSignToggle {
                    Button {
                        state.toggleAmountSign()
                    } label: {
                        Image(systemName: "plus.forwardslash.minus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change amount sign")
                }
            }
        }
    }

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if state.accounts.isEmpty {
                Text("Add an account first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.accounts) { account in
                            AccountChip(
                                account: account,
                                isSelected: state.selectedAccountID == account.id
                            )
                            .onTapGesture { state.selectedAccountID = account.id }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            CategoryDrillDownPicker(
                groups: state.visibleGroups,
                kind: state.kind.categoryKind,
                pinnedCategory: state.pinnedCategoryForPicker,
                selectedCategoryID: $state.selectedCategoryID,
                selectedCategory: state.selectedCategory
            )

            if let suggestionNote = state.suggestionNote {
                Text(suggestionNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack {
                    Text("Date")
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    DatePicker(
                        "",
                        selection: $state.occurredAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                }
                .detailRow()

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text("Payee")
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    TextField("Optional", text: $state.payee)
                        .multilineTextAlignment(.trailing)
                }
                .detailRow()

                Divider()
                    .padding(.leading, 14)

                HStack(alignment: .top) {
                    Text("Note")
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    TextField("Optional", text: $state.note, axis: .vertical)
                        .lineLimit(1...3)
                        .multilineTextAlignment(.trailing)
                        .focused($noteFocused)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
        }
    }
}

extension View {
    fileprivate func detailRow() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 46)
    }
}
