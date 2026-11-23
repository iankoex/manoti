//
//  IdentifierEditorView.swift
//  AccountsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

struct IdentifierEditorView: View {
    let account: Account

    @Environment(AccountService.self) private var accountService

    @State private var identifiers: [AccountIdentifier] = []
    @State private var editorTarget: IdentifierEditorTarget?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if identifiers.isEmpty {
                    Text("No identifiers yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(identifiers) { identifier in
                        Button {
                            editorTarget = .edit(identifier)
                        } label: {
                            IdentifierRow(identifier: identifier)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                remove(identifier)
                            }
                        }
                    }
                }
            } header: {
                Text("Identifiers")
            } footer: {
                Text(
                    "Manoti checks card last-4 first, then account number, phone and sender. The same value cannot point at two accounts."
                )
            }
        }
        .navigationTitle("Message identifiers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add identifier", systemImage: "plus") {
                    editorTarget = .create
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            IdentifierFormView(account: account, identifier: target.identifier)
        }
        .onManotiDataChange { reload() }
        .alert(
            "Could not remove identifier",
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

    private func reload() {
        identifiers = (account.identifiers ?? []).sorted {
            if $0.type.specificity != $1.type.specificity {
                return $0.type.specificity < $1.type.specificity
            }

            if $0.value != $1.value {
                return $0.value < $1.value
            }

            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func remove(_ identifier: AccountIdentifier) {
        do {
            try accountService.removeIdentifier(identifier)
            // Drop the model from the local array before the refresh notification arrives so
            // the list never renders a deleted SwiftData object.
            identifiers.removeAll { $0 === identifier }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum IdentifierEditorTarget: Identifiable {
    case create
    case edit(AccountIdentifier)

    var id: String {
        switch self {
            case .create: "create"
            case .edit(let identifier): identifier.id.uuidString
        }
    }

    var identifier: AccountIdentifier? {
        switch self {
            case .create: nil
            case .edit(let identifier): identifier
        }
    }
}

private struct IdentifierRow: View {
    let identifier: AccountIdentifier

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: identifier.type.symbolName)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(identifier.type.displayName)
                    .font(.subheadline.weight(.medium))

                Text(displayValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var displayValue: String {
        identifier.type == .cardLast4 ? "•••• \(identifier.value)" : identifier.value
    }

    private var accessibilityText: String {
        switch identifier.type {
            case .cardLast4: "Card ending in \(identifier.value)"
            case .accountNumber: "Account number \(identifier.value)"
            case .phone: "Phone number \(identifier.value)"
            case .sender: "Sender \(identifier.value)"
        }
    }
}
