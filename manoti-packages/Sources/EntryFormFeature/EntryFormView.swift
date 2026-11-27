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
private enum EntryFormField: Hashable {
    case amount
    case counterpartAmount
    case fee
    case note
    case line(UUID)
}

private enum TagPickerTarget: Identifiable {
    case single
    case line(UUID)

    var id: String {
        switch self {
            case .single: "single"
            case .line(let id): id.uuidString
        }
    }
}

public struct EntryFormView: View {
    @Bindable private var state: EntryFormState
    private let showsKindControl: Bool
    private let footer: AnyView
    private let splitTemplate: SplitTemplate?

    @FocusState private var focusedField: EntryFormField?
    @State private var tagPickerTarget: TagPickerTarget?

    public init(
        state: EntryFormState,
        showsKindControl: Bool = false,
        splitTemplate: SplitTemplate? = nil
    ) {
        _state = Bindable(state)
        self.showsKindControl = showsKindControl
        self.splitTemplate = splitTemplate
        self.footer = AnyView(EmptyView())
    }

    public init<Footer: View>(
        state: EntryFormState,
        showsKindControl: Bool = false,
        splitTemplate: SplitTemplate? = nil,
        @ViewBuilder footer: () -> Footer
    ) {
        _state = Bindable(state)
        self.showsKindControl = showsKindControl
        self.splitTemplate = splitTemplate
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

                    if state.isTransferForm, state.transferNeedsCounterpartAmount {
                        transferCounterpartAmountField
                    }

                    if state.isTransferForm {
                        transferAccountsSection
                    } else {
                        accountPicker
                    }

                    if state.showsCategory, !state.isSplit {
                        if let template = splitTemplate, let summary = splitTemplateSummary(template) {
                            splitTemplateButton(template, summary: summary)
                        }

                        splitButton
                    }

                    if let validationHint {
                        Text(validationHint)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if state.isTransferForm {
                        Text("A transfer has no category.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if state.showsCategory {
                        if state.isSplit {
                            splitEditor
                        } else {
                            categoryPicker
                            tagsRow
                        }
                    }

                    detailsSection
                    footer
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            // The system keyboard is the only keypad now; start on the total.
            guard !state.isLinkedEntry else {
                return
            }

            focusedField = .amount
        }
        .sheet(item: $tagPickerTarget) { target in
            switch target {
                case .single:
                    TagPickerSheet(
                        selection: Binding(
                            get: { state.selectedTagIDs },
                            set: { state.selectedTagIDs = $0 }
                        ),
                        onCreated: { state.availableTags.append($0) }
                    )

                case .line(let id):
                    TagPickerSheet(
                        selection: Binding(
                            get: { state.lineDrafts?.first { $0.id == id }?.tagIDs ?? [] },
                            set: { newValue in
                                guard let index = state.lineDrafts?.firstIndex(where: { $0.id == id }) else {
                                    return
                                }

                                state.lineDrafts?[index].tagIDs = newValue
                            }
                        ),
                        onCreated: { state.availableTags.append($0) }
                    )
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

        // The split editor's footer already shows the running total and the difference.
        if state.isSplit, !state.isTransferForm, state.splitValidationMessage != nil {
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
            if state.isTypeEditable {
                Picker(
                    "Type",
                    selection: Binding(
                        get: { state.type },
                        set: { state.setType($0) }
                    )
                ) {
                    ForEach(state.typeOptions) { type in
                        Text(type.displayName).tag(type)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    state.isTransferForm
                        ? "\(state.transferAmountLabel) · \(state.currency.code)"
                        : state.currency.code
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                TextField("0", text: amountTextBinding)
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
                feeField

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

    private var amountTextBinding: Binding<String> {
        Binding(
            get: { state.amountText },
            set: { newValue in
                state.amountText = EntryFormState.sanitisedAmountText(
                    newValue,
                    exponent: state.currency.exponent,
                    allowsNegative: state.supportsSignToggle
                )
            }
        )
    }

    private var feeTextBinding: Binding<String> {
        Binding(
            get: { state.feeText },
            set: { newValue in
                let currency = state.isTransferForm ? state.transferFeeCurrency : state.currency
                state.feeText = EntryFormState.sanitisedAmountText(
                    newValue,
                    exponent: currency.exponent
                )
            }
        )
    }

    private var counterpartAmountTextBinding: Binding<String> {
        Binding(
            get: { state.counterpartAmountText },
            set: { newValue in
                state.counterpartAmountText = EntryFormState.sanitisedAmountText(
                    newValue,
                    exponent: state.transferCounterpartCurrency.exponent
                )
            }
        )
    }

    private var feeField: some View {
        HStack(spacing: 4) {
            Text("Fee")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("0", text: feeTextBinding)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 58, height: 22, alignment: .trailing)
                .padding(.trailing, 2)
                .decimalKeyboard()
                .focused($focusedField, equals: .fee)
                .accessibilityLabel("Fee")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.35), in: .capsule)
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

    private var transferCounterpartAmountField: some View {
        HStack(spacing: 10) {
            Text(state.transferCounterpartAmountLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("0", text: counterpartAmountTextBinding)
                .font(.headline)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .decimalKeyboard()
                .focused($focusedField, equals: .counterpartAmount)
                .accessibilityLabel(state.transferCounterpartAmountLabel)

            Text(state.transferCounterpartCurrency.code)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
    }

    /// Two account strips, the same account cards the one-account form uses. From and To
    /// each take one tap; there is no menu to open first.
    private var transferAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountChipRow(
                title: "From",
                accounts: transferSourceAccounts,
                selectedID: state.transferSourceID,
                disabledID: nil
            ) { id in
                state.selectTransferSource(id)
            }

            accountChipRow(
                title: "To",
                accounts: transferDestinationAccounts,
                selectedID: state.transferDestinationID,
                disabledID: state.transferSourceID
            ) { id in
                state.selectTransferDestination(id)
            }

            if state.knownSideAccounts.isEmpty {
                Text("Add an account in \(state.currency.code) first.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transferSourceAccounts: [Account] {
        state.kind == .transferOut ? state.knownSideAccounts : state.counterpartAccounts
    }

    private var transferDestinationAccounts: [Account] {
        state.kind == .transferIn ? state.knownSideAccounts : state.counterpartAccounts
    }

    private func accountChipRow(
        title: String,
        accounts: [Account],
        selectedID: UUID?,
        disabledID: UUID?,
        onSelect: @escaping (UUID) -> Void
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
                            let isDisabled = account.id == disabledID

                            AccountChip(
                                account: account,
                                isSelected: selectedID == account.id
                            )
                            .opacity(isDisabled ? 0.35 : 1)
                            .disabled(isDisabled)
                            .allowsHitTesting(!isDisabled)
                            .onTapGesture {
                                guard !isDisabled else {
                                    return
                                }

                                onSelect(account.id)
                            }
                            .accessibilityHint(
                                isDisabled ? "Already selected on the other side." : ""
                            )
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

    private var tagsRow: some View {
        Button {
            focusedField = nil
            tagPickerTarget = .single
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text("Tags")
                    .font(.subheadline)

                Spacer(minLength: 12)

                Text(tagSummary(for: state.selectedTagIDs))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func splitTemplateSummary(_ template: SplitTemplate) -> String? {
        let names = Dictionary(uniqueKeysWithValues: state.categories.map { ($0.id, $0.name) })
        return template.summary(categoryNames: names)
    }

    private func splitTemplateButton(_ template: SplitTemplate, summary: String) -> some View {
        Button {
            focusedField = .amount
            state.applySplitTemplate(template)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Split like last time")
                        .font(.subheadline.weight(.medium))

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var splitButton: some View {
        Button {
            focusedField = .amount
            state.beginSplit()
        } label: {
            Label("Split into lines", systemImage: "square.split.2x1")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .padding(.vertical, 2)
    }

    private var splitEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lines")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("One line") {
                    focusedField = .amount
                    state.endSplit()
                }
                .font(.caption.weight(.medium))
            }

            ForEach(state.lineDrafts ?? []) { draft in
                splitRow(draft)
            }

            HStack(spacing: 12) {
                Button {
                    if let id = state.addLine() {
                        focusedField = .line(id)
                    }
                } label: {
                    Label("Add line", systemImage: "plus.circle")
                }

                Spacer()

                if state.splitRemainderMinor > 0 {
                    Button("Add remainder line") {
                        if let id = state.addRemainderLine() {
                            focusedField = .line(id)
                        }
                    }
                }
            }
            .font(.caption.weight(.medium))
            .padding(.top, 2)

            Text(remainderText)
                .font(.caption)
                .foregroundStyle(AnyShapeStyle(state.splitRemainderMinor == 0 ? Color.secondary : Color.orange))
        }
    }

    private func splitRow(_ draft: LineDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("0", text: amountBinding(for: draft.id))
                    .decimalKeyboard()
                    .focused($focusedField, equals: .line(draft.id))
                    .multilineTextAlignment(.leading)
                    .monospacedDigit()
                    .font(.headline)
                    .frame(maxWidth: 130, alignment: .leading)

                Text(state.currency.code)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if (state.lineDrafts?.count ?? 0) > 1 {
                    Button {
                        state.removeLine(draft.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove line")
                }
            }

            CategoryDrillDownPicker(
                groups: state.visibleGroups,
                kind: state.kind.categoryKind,
                pinnedCategory: nil,
                selectedCategoryID: categoryBinding(for: draft.id),
                selectedCategory: state.categories.first { $0.id == draft.categoryID }
            )

            Button {
                focusedField = nil
                tagPickerTarget = .line(draft.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.caption2.weight(.semibold))
                    Text(tagSummary(for: draft.tagIDs))
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 14))
    }

    private var remainderText: String {
        let total = Money(minorUnits: state.linesTotalMinor, currency: state.currency).formatted()
        let entry = Money(minorUnits: state.parsedAmount?.minorUnits ?? 0, currency: state.currency).formatted()

        guard state.splitRemainderMinor != 0 else {
            return "Lines add up to \(total)"
        }

        let remaining = Money(minorUnits: abs(state.splitRemainderMinor), currency: state.currency)
            .formatted()
        return state.splitRemainderMinor > 0
            ? "Lines add up to \(total) of \(entry) · \(remaining) left"
            : "Lines add up to \(total) of \(entry) · \(remaining) over"
    }

    private func tagSummary(for ids: Set<UUID>) -> String {
        let names = state.tagObjects(for: ids).map(\.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private func amountBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { state.lineDrafts?.first { $0.id == id }?.amountText ?? "" },
            set: { newValue in
                guard let index = state.lineDrafts?.firstIndex(where: { $0.id == id }) else {
                    return
                }

                state.lineDrafts?[index].amountText = EntryFormState.sanitisedAmountText(
                    newValue,
                    exponent: state.currency.exponent
                )
            }
        )
    }

    private func categoryBinding(for id: UUID) -> Binding<UUID?> {
        Binding(
            get: { state.lineDrafts?.first { $0.id == id }?.categoryID },
            set: { newValue in
                guard let index = state.lineDrafts?.firstIndex(where: { $0.id == id }) else {
                    return
                }

                state.lineDrafts?[index].categoryID = newValue
            }
        )
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

                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("Optional", text: $state.payee)
                            .multilineTextAlignment(.trailing)

                        if !state.channelName.isEmpty {
                            Text("via \(state.channelName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if state.entry?.isConfirmationOnly == true {
                            Text("From a bank receipt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                        .focused($focusedField, equals: .note)
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
