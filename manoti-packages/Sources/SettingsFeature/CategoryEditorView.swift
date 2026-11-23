//
//  CategoryEditorView.swift
//  SettingsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for adding or editing one spending category.
struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CategoryService.self) private var categoryService

    @Bindable private var state: CategoryEditorState
    @State private var errorMessage: String?

    init(
        category: SpendingCategory?,
        groups: [CategoryGroup],
        categories: [SpendingCategory],
        displayCurrency: Currency
    ) {
        _state = Bindable(
            CategoryEditorState(
                category: category,
                groups: groups,
                categories: categories,
                displayCurrency: displayCurrency
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                appearanceSection
                budgetSection
                if !state.isNew {
                    archiveSection
                }
            }
            .navigationTitle(state.isNew ? "New category" : "Edit category")
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

    private var detailsSection: some View {
        Section {
            TextField("Name", text: $state.name)

            if state.groups.isEmpty {
                Text("No groups available. Add a group before creating a category.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Group", selection: $state.groupID) {
                    ForEach(state.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Use for")
                    .font(.subheadline)

                Picker("Use for", selection: $state.kind) {
                    ForEach(CategoryKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Use for")
            }
        } footer: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                if let message = state.validationMessage,
                    !state.name.isEmpty || !state.monthlyDefaultText.isEmpty
                {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("A category name must be unique within its group.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(ManotiPalette.categoryColours, id: \.self) { hex in
                    ColourSwatch(hex: hex, isSelected: isSelectedColour(hex))
                        .onTapGesture { state.colorHex = hex }
                }
            }
            .padding(.vertical, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(ManotiPalette.categorySymbols, id: \.self) { symbol in
                    SymbolSwatch(
                        symbol: symbol,
                        hex: state.colorHex,
                        isSelected: state.symbolName == symbol
                    )
                    .onTapGesture { state.symbolName = symbol }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var budgetSection: some View {
        Section {
            Toggle("Fixed expense", isOn: $state.isFixed)

            LabeledContent("Monthly default") {
                HStack(spacing: ManotiSpacing.small) {
                    Text(state.displayCurrency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0.00", text: $state.monthlyDefaultText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }

            TextField("Keywords", text: $state.keywords)
        } footer: {
            Text(
                "The monthly default is optional. Keywords are separated by commas and matched case-insensitively when suggesting a category."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var archiveSection: some View {
        Section {
            Toggle("Archived", isOn: $state.isArchived)
        } footer: {
            Text("Archived categories keep their history but are hidden from pickers and suggestions.")
        }
    }

    private func save() {
        do {
            try state.save(using: categoryService)
            dismiss()
        } catch CategoryEditorState.ValidationError.invalid {
            errorMessage = state.validationMessage ?? "Check the category details and try again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isSelectedColour(_ hex: String) -> Bool {
        let current = state.colorHex.hasPrefix("#") ? String(state.colorHex.dropFirst()) : state.colorHex
        let candidate = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return current.caseInsensitiveCompare(candidate) == .orderedSame
    }
}

private struct ColourSwatch: View {
    let hex: String
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(ManotiColor.forHex(hex))
            .frame(width: 28, height: 28)
            .overlay {
                Circle()
                    .strokeBorder(.primary, lineWidth: isSelected ? 2 : 0)
                    .padding(-3)
            }
            .accessibilityLabel(hex)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SymbolSwatch: View {
    let symbol: String
    let hex: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(ManotiColor.forHex(hex))
            .frame(width: 34, height: 34)
            .background(
                ManotiColor.forHex(hex).opacity(isSelected ? 0.22 : 0.08),
                in: .rect(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ManotiColor.forHex(hex), lineWidth: isSelected ? 2 : 0)
            }
            .accessibilityLabel(symbol)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
