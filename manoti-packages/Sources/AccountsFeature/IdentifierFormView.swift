//
//  IdentifierFormView.swift
//  AccountsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

struct IdentifierFormView: View {
    let account: Account
    let identifier: AccountIdentifier?

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService

    @State private var type: AccountIdentifierType
    @State private var value: String
    @State private var errorMessage: String?
    @State private var isConfirmingRemoval = false

    init(account: Account, identifier: AccountIdentifier?) {
        self.account = account
        self.identifier = identifier
        _type = State(initialValue: identifier?.type ?? .cardLast4)
        _value = State(initialValue: identifier?.value ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(AccountIdentifierType.allCases) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                }

                Section {
                    if type.usesNumericKeyboard {
                        TextField(type.valuePlaceholder, text: $value)
                            .decimalKeyboard()
                    } else {
                        TextField(type.valuePlaceholder, text: $value)
                            .plainTextInput()
                    }
                } header: {
                    Text("Value")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text(type.validationHint)
                    }
                }

                if identifier != nil {
                    Section {
                        Button("Remove identifier", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                    }
                }
            }
            .navigationTitle(identifier == nil ? "Add identifier" : "Edit identifier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: type) { _, _ in
                // A value entered for one type may be meaningless for another, so start over.
                value = ""
                errorMessage = nil
            }
            .onChange(of: value) { _, _ in
                errorMessage = nil
            }
            .confirmationDialog(
                "Remove this identifier?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove identifier", role: .destructive, action: removeIdentifier)
            } message: {
                Text("Messages that use it will no longer be matched to this account.")
            }
        }
    }

    private func save() {
        do {
            if let identifier {
                try accountService.updateIdentifier(identifier, value: value, type: type)
            } else {
                try accountService.addIdentifier(value: value, type: type, to: account)
            }

            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func removeIdentifier() {
        guard let identifier else {
            return
        }

        do {
            try accountService.removeIdentifier(identifier)
            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
            case AccountError.invalidIdentifier:
                "Check the value. \(type.validationHint)"
            case AccountError.duplicateIdentifier:
                "That identifier is already attached to another account."
            default:
                error.localizedDescription
        }
    }
}
