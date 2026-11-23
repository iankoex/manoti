//
//  TransferView.swift
//  TransfersFeature
//

import AppModels
import AppServices
import SwiftUI

/// Standalone transfer sheet (opened from Home). The Add sheet embeds `TransferFormView` directly.
public struct TransferView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService
    @Environment(TransferService.self) private var transferService

    @State private var state: TransferFormState
    @State private var errorMessage: String?

    public init(from account: Account? = nil) {
        _state = State(initialValue: TransferFormState(initialFrom: account?.id))
    }

    public var body: some View {
        NavigationStack {
            TransferFormView(state: state)
                .navigationTitle("Transfer")
                .navigationBarTitleDisplayModeInlineCompat()
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
                    state.reload(accountService: accountService)
                    state.selectDefaults()
                }
        }
    }

    private func save() {
        do {
            try state.save(transferService: transferService)
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
