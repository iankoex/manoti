//
//  AccountDetailView.swift
//  AccountsFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import LedgerFeature
import Modifiers
import SwiftUI

public struct AccountDetailView: View {
    let account: Account

    @Environment(AccountService.self) private var accountService
    @Environment(LedgerService.self) private var ledgerService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var isAdjusting = false
    @State private var isEditing = false
    @State private var targetText = ""
    @State private var identifierCount = 0
    @State private var errorMessage: String?
    @State private var pendingDeletion: LedgerEntry?
    @State private var deleteErrorMessage: String?

    public init(account: Account) {
        self.account = account
    }

    public var body: some View {
        List {
            Section {
                balanceHeader
            }

            Section {
                NavigationLink {
                    IdentifierEditorView(account: account)
                } label: {
                    HStack(spacing: 12) {
                        Label("Message identifiers", systemImage: "text.bubble")

                        Spacer()

                        Text(identifierCount == 0 ? "Add" : "\(identifierCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Used to match incoming bank and mobile money messages to this account.")
            }

            Section("History") {
                if entries.isEmpty {
                    Text("No entries yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink {
                            LedgerEntryDetailView(entry: entry)
                        } label: {
                            LedgerEntryRowView(entry: entry)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletion = entry
                            }
                        }
                        .alert("Delete entry?", isPresented: deleteConfirmationBinding(for: entry)) {
                            Button("Cancel", role: .cancel) {
                                pendingDeletion = nil
                            }
                            Button("Delete", role: .destructive) {
                                delete(entry)
                            }
                        } message: {
                            Text("This removes the entry from account balances. It can't be undone from the app.")
                        }
                    }
                }
            }
        }
        .navigationTitle(account.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit account", systemImage: "pencil") {
                        isEditing = true
                    }

                    Button("Set balance…", systemImage: "slider.horizontal.3") {
                        targetText = amountsHidden ? "" : account.balance.decimalValue.description
                        isAdjusting = true
                    }

                    Button("Archive account", systemImage: "archivebox", role: .destructive) {
                        archive()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            AccountEditorView(account: account)
        }
        .alert("Set balance", isPresented: $isAdjusting) {
            TextField("New balance", text: $targetText)
                .decimalKeyboard()
            Button("Cancel", role: .cancel) {}
            Button("Apply", action: applyAdjustment)
        } message: {
            Text("An adjustment entry records the difference.")
        }
        .alert(
            "Could not update account",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Could not delete entry",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .onManotiDataChange { reload() }
    }

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: account.symbolName)
                    .foregroundStyle(ManotiColor.forHex(account.colorHex))
                Text("\(account.kind.displayName) · \(account.currency.code)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            AmountText(account.balance, style: .largeTitle.weight(.semibold))
        }
        .padding(.vertical, 6)
    }

    private var entries: [LedgerEntry] {
        (account.transactions ?? [])
            .filter(\.isPosted)
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private func reload() {
        identifierCount = account.identifiers?.count ?? 0
    }

    private func deleteConfirmationBinding(for entry: LedgerEntry) -> Binding<Bool> {
        Binding(
            get: { pendingDeletion?.id == entry.id },
            set: { isPresented in
                if !isPresented, pendingDeletion?.id == entry.id {
                    pendingDeletion = nil
                }
            }
        )
    }

    private func delete(_ entry: LedgerEntry) {
        do {
            try ledgerService.delete(entry)
        } catch {
            deleteErrorMessage = error.localizedDescription
        }

        pendingDeletion = nil
    }

    private func applyAdjustment() {
        do {
            let parsed = MoneyParser.parse(targetText, defaultCurrency: account.currency)
            guard let parsed, parsed.money.minorUnits != account.balance.minorUnits else {
                return
            }

            let delta = parsed.money.minorUnits - account.balance.minorUnits
            try ledgerService.record(
                kind: .adjustment,
                amountMinor: delta,
                account: account,
                lines: [],
                note: "Balance adjustment"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive() {
        do {
            try accountService.archive(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
