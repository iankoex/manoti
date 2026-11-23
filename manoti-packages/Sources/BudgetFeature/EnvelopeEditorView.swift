//
//  EnvelopeEditorView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for adding or editing one category envelope.
public struct EnvelopeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.manotiAmountsHidden) private var amountsHidden
    @Environment(AppService.self) private var appService
    @Environment(BudgetService.self) private var budgetService
    @Environment(CategoryService.self) private var categoryService

    @Bindable private var state: EnvelopeEditorState
    @State private var errorMessage: String?

    public init(period: BudgetPeriod, envelope: Envelope? = nil) {
        _state = Bindable(EnvelopeEditorState(period: period, envelope: envelope))
    }

    public var body: some View {
        NavigationStack {
            Form {
                categorySection
                limitSection
                rolloverSection
                noteSection
            }
            .navigationTitle(state.envelope == nil ? "New envelope" : "Edit envelope")
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
                state.setDisplayCurrency(appService.displayCurrency)

                do {
                    try state.reload(categoryService: categoryService)
                    try state.refreshSuggestion(using: budgetService)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: state.categoryID) { _, _ in
                do {
                    try state.refreshSuggestion(using: budgetService)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var categorySection: some View {
        Section {
            if state.categories.isEmpty {
                Text("No active categories available.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: $state.categoryID) {
                    ForEach(state.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .disabled(state.envelope != nil)
            }
        } footer: {
            if state.envelope != nil {
                Text("Create a new envelope to budget a different category.")
            } else if state.categories.isEmpty {
                Text("Unarchive or add a spending category before setting an envelope.")
            } else if let category = state.selectedCategory, category.isFixed {
                Text("Fixed categories are committed costs and are excluded from safe to spend.")
            }
        }
    }

    private var limitSection: some View {
        Section {
            LabeledContent("Limit") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.displayCurrency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $state.limitText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                if let message = state.validationMessage, !state.limitText.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let suggestion = state.suggestedLimit, !amountsHidden {
                    HStack(spacing: ManotiSpacing.small) {
                        Text("Last period:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        MaskedAmountText(suggestion, style: .caption)

                        Spacer()

                        Button("Use") {
                            state.applySuggestion()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                Text("A limit of zero keeps the category visible without capping it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rolloverSection: some View {
        Section {
            Toggle("Carry over unused money", isOn: $state.rolloverEnabled)
        } footer: {
            Text("The previous period's remaining amount, positive or negative, is added to this envelope.")
        }
    }

    private var noteSection: some View {
        Section("Note") {
            TextField("Optional note", text: $state.note, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private func save() {
        do {
            try state.save(using: budgetService)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
