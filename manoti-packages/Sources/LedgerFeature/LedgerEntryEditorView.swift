//
//  LedgerEntryEditorView.swift
//  LedgerFeature
//

import AppModels
import AppServices
import EntryFormFeature
import Modifiers
import SwiftUI

/// Sheet for editing one ledger entry, using the form shared with Add and Inbox review.
public struct LedgerEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(CategoryService.self) private var categoryService
    @Environment(TagService.self) private var tagService
    @Environment(LedgerService.self) private var ledgerService
    @Environment(TransferService.self) private var transferService

    @State private var state: EntryFormState
    @State private var isConfirmingConversion = false
    @State private var errorMessage: String?

    public init(entry: LedgerEntry) {
        _state = State(initialValue: EntryFormState(purpose: .edit, entry: entry))
    }

    public var body: some View {
        NavigationStack {
            EntryFormView(state: state, showsKindControl: true)
                .navigationTitle(title)
                .navigationBarTitleDisplayModeInlineCompat()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: dismiss.callAsFunction)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Update", action: save)
                            .buttonStyle(.glassProminent)
                            .disabled(!state.canSave)
                    }
                }
                .task {
                    state.reload(accountService: accountService, categoryService: categoryService, tagService: tagService)
                }
                .confirmationDialog(
                    "Turn this entry into a transfer?",
                    isPresented: $isConfirmingConversion,
                    titleVisibility: .visible
                ) {
                    Button("Convert to transfer", role: .destructive) { performSave() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The split lines and tags on this entry will be removed. A transfer has no categories.")
                }
                .alert(
                    "Could not update",
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

    private func save() {
        if state.conversionDropsSplitOrTags {
            isConfirmingConversion = true
            return
        }

        performSave()
    }

    private func performSave() {
        do {
            if state.convertsToTransfer {
                _ = try state.save(ledger: ledgerService, transfer: transferService)
                dismiss()
                return
            }

            try state.save(ledger: ledgerService)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var title: String {
        if state.isTransferForm || state.kind.isTransferLeg {
            return "Edit transfer"
        }

        switch state.kind {
            case .expense, .income:
                return "Edit payment"
            default:
                return "Edit entry"
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
