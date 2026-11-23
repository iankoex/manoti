//
//  InboxDetailView.swift
//  InboxFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

struct InboxDetailView: View {
    let entry: LedgerEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(InboxService.self) private var inboxService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var accounts: [Account] = []
    @State private var suggestions: [CategorySuggestion] = []
    @State private var selectedAccountID: UUID?
    @State private var selectedCategoryID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    LabeledContent(
                        "Amount",
                        value: AmountMask.money(
                            Money(minorUnits: entry.amountMinor, currency: entry.currency),
                            hidden: amountsHidden
                        )
                    )
                    LabeledContent("Type", value: entry.kind.displayName)

                    if !entry.payee.isEmpty {
                        LabeledContent("From", value: entry.payee)
                    }

                    LabeledContent(
                        "When",
                        value: entry.occurredAt.formatted(date: .abbreviated, time: .shortened)
                    )

                    if entry.feeMinor != 0 {
                        LabeledContent("Fee", value: AmountMask.money(entry.fee, hidden: amountsHidden))
                    }
                }

                Section("Account") {
                    if accounts.isEmpty {
                        Text("No active \(entry.currency.code) account. Add one in Accounts first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Account", selection: $selectedAccountID) {
                        Text("Choose an account").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text("\(account.displayName) · \(account.currency.code)")
                                .tag(Optional(account.id))
                        }
                    }
                }

                Section("Category") {
                    if suggestions.isEmpty {
                        Text("No suggestion yet. Pick a category later from the ledger.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions) { suggestion in
                                    VStack(spacing: 2) {
                                        CategoryChip(
                                            category: suggestion.category,
                                            isSelected: selectedCategoryID == suggestion.category.id
                                        )
                                        .onTapGesture { selectedCategoryID = suggestion.category.id }

                                        Text("\(Int(suggestion.confidence * 100))% · \(suggestion.reason)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !entry.rawMessage.isEmpty {
                    Section("Original message") {
                        if amountsHidden {
                            AmountsHiddenPlaceholder("Message hidden")
                        } else {
                            DisclosureGroup("Show text") {
                                Text(entry.rawMessage)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Ignore this message", role: .destructive, action: ignore)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", action: confirm)
                        .buttonStyle(.glassProminent)
                        .disabled(!hasValidAccountSelection)
                }
            }
            .task { load() }
        }
    }

    private var hasValidAccountSelection: Bool {
        guard let selectedAccountID else {
            return false
        }

        return accounts.contains { $0.id == selectedAccountID }
    }

    private func load() {
        accounts = ((try? accountService.fetchAccounts()) ?? []).filter {
            entry.currencyCode.isEmpty || $0.currencyCode == entry.currencyCode
        }
        suggestions = (try? inboxService.suggestions(for: entry)) ?? []

        if let linkedID = entry.account?.id, accounts.contains(where: { $0.id == linkedID }) {
            selectedAccountID = linkedID
        } else {
            selectedAccountID = accounts.first?.id
        }

        selectedCategoryID = suggestions.first?.category.id
    }

    private func confirm() {
        let account = accounts.first { $0.id == selectedAccountID }
        let category = suggestions.map(\.category).first { $0.id == selectedCategoryID }

        do {
            try inboxService.confirm(entry, account: account, category: category)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ignore() {
        do {
            try inboxService.ignore(entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func navigationBarTitleDisplayModeInlineCompat() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
