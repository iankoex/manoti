//
//  InboxDetailView.swift
//  InboxFeature
//

import AppModels
import AppServices
import EntryFormFeature
import Modifiers
import SwiftUI

struct InboxDetailView: View {
    let entry: LedgerEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(CategoryService.self) private var categoryService
    @Environment(TagService.self) private var tagService
    @Environment(LedgerService.self) private var ledgerService
    @Environment(InboxService.self) private var inboxService
    @Environment(TransferService.self) private var transferService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var state: EntryFormState
    @State private var alwaysFile = false
    @State private var splitTemplate: SplitTemplate?
    @State private var possibleDuplicate: LedgerEntry?
    @State private var isConfirmingIgnore = false
    @State private var isConfirmingConversion = false
    @State private var errorMessage: String?

    init(entry: LedgerEntry) {
        self.entry = entry
        _state = State(initialValue: EntryFormState(purpose: .review, entry: entry))
    }

    var body: some View {
        NavigationStack {
            EntryFormView(state: state, showsKindControl: true, splitTemplate: splitTemplate) {
                footer
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
                        .disabled(!state.canSave)
                }
            }
            .task { load() }
            .alert(
                "Could not update this entry",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Ignore this message?",
                isPresented: $isConfirmingIgnore,
                titleVisibility: .visible
            ) {
                Button("It isn't a transaction") { ignore(.notATransaction) }
                Button("I recorded it elsewhere") { ignore(.duplicate) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Manoti remembers this message pattern so it needs less attention next time.")
            }
            .confirmationDialog(
                "Turn this entry into a transfer?",
                isPresented: $isConfirmingConversion,
                titleVisibility: .visible
            ) {
                Button("Convert to transfer", role: .destructive) { performConfirm() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The split lines and tags on this entry will be removed. A transfer has no categories.")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let possibleDuplicate {
            Label {
                Text(
                    "Possible duplicate of \(duplicateTitle(possibleDuplicate)). Nothing is linked automatically."
                )
            } icon: {
                Image(systemName: "questionmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !entry.rawMessage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Original message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if amountsHidden {
                    AmountsHiddenPlaceholder("Message hidden")
                } else {
                    DisclosureGroup("Show text") {
                        Text(entry.rawMessage)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .font(.subheadline)
                }
            }
        }

        if !entry.payee.isEmpty, !state.isSplit, !state.isTransferForm {
            Toggle(isOn: $alwaysFile) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always file this merchant here")
                        .font(.subheadline)

                    Text("Skips Review for \(entry.payee) once the category is confident.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Button(role: .destructive) {
            isConfirmingIgnore = true
        } label: {
            Text("Ignore this message")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func load() {
        state.reload(accountService: accountService, categoryService: categoryService, tagService: tagService)
        let suggestions = (try? inboxService.suggestions(for: entry)) ?? []
        state.applySuggestion(suggestions.first)

        // Routing could not identify the account; the merchant's own history is a
        // better guess than the first account in the list.
        if entry.account == nil, let account = inboxService.suggestedAccount(for: entry) {
            state.selectedAccountID = account.id
        }

        alwaysFile = inboxService.autoApply(for: entry.payee)
        splitTemplate = try? inboxService.splitTemplate(for: entry)
        possibleDuplicate = inboxService.possibleDuplicate(of: entry)
    }

    private func confirm() {
        if state.conversionDropsSplitOrTags {
            isConfirmingConversion = true
            return
        }

        performConfirm()
    }

    private func performConfirm() {
        do {
            if state.convertsToTransfer {
                _ = try state.save(ledger: ledgerService, transfer: transferService)
                dismiss()
                return
            }

            // Apply the edited fields first, then confirm so the status flips and the
            // merchant/category learning is recorded.
            try state.save(ledger: ledgerService)
            try inboxService.confirm(
                entry,
                account: state.selectedAccount,
                category: state.selectedCategory
            )

            if !entry.payee.isEmpty {
                try inboxService.setAutoApply(alwaysFile, for: entry.payee)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ignore(_ reason: IngestMemoryReason) {
        do {
            try inboxService.ignore(entry, reason: reason)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicateTitle(_ entry: LedgerEntry) -> String {
        let name = entry.payee.isEmpty ? entry.kind.displayName : entry.payee
        let when = entry.occurredAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "\(name) on \(when)"
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
