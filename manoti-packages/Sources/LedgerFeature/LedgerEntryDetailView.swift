//
//  LedgerEntryDetailView.swift
//  LedgerFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Read-only detail for one ledger entry, with edit and delete for manual rows.
public struct LedgerEntryDetailView: View {
    private let entry: LedgerEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(LedgerService.self) private var ledgerService

    @State private var isShowingEditor = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    public init(entry: LedgerEntry) {
        self.entry = entry
    }

    public var body: some View {
        List {
            Section {
                header
            }

            Section("Details") {
                facts
            }

            if isLinked {
                Section {
                    Label(linkedExplanation, systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayModeInlineCompat()
        .toolbar {
            if !isLinked {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") {
                        edit()
                    }

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .confirmationDialog("Delete entry?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("This removes the entry from account balances. It can't be undone from the app.")
        }
        .sheet(isPresented: $isShowingEditor) {
            LedgerEntryEditorView(entry: entry)
        }
        .alert(
            "Could not delete entry",
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

    private var header: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack(spacing: ManotiSpacing.medium) {
                Image(systemName: LedgerEntryPresentation.symbolName(for: entry))
                    .font(.headline)
                    .foregroundStyle(LedgerEntryPresentation.tint(for: entry))
                    .frame(width: 40, height: 40)
                    .background(LedgerEntryPresentation.tint(for: entry).opacity(0.12), in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LedgerEntryPresentation.title(for: entry))
                        .font(.headline)
                        .lineLimit(2)

                    Text(
                        "\(entry.kind.displayName) · \(entry.occurredAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            AmountText(
                Money(minorUnits: entry.signedAmountMinor, currency: entry.currency),
                showsSign: true,
                style: .title2.weight(.semibold)
            )

            if entry.feeMinor != 0 {
                HStack(spacing: ManotiSpacing.tiny) {
                    Text("Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MaskedAmountText(entry.fee, style: .caption)
                }
            }
        }
        .padding(.vertical, ManotiSpacing.small)
    }

    @ViewBuilder
    private var facts: some View {
        if let account = entry.account {
            LabeledContent("Account") {
                factValue(
                    account.displayName,
                    symbolName: account.symbolName,
                    tint: ManotiColor.forHex(account.colorHex)
                )
            }
        }

        if let category = entry.category {
            LabeledContent("Category") {
                factValue(
                    category.name,
                    symbolName: category.symbolName,
                    tint: ManotiColor.forHex(category.colorHex)
                )
            }
        }

        if !entry.payee.isEmpty {
            LabeledContent("Payee", value: entry.payee)
        }

        if !entry.note.isEmpty {
            LabeledContent("Note") {
                Text(entry.note)
                    .multilineTextAlignment(.trailing)
            }
        }

        LabeledContent("Source", value: LedgerEntryPresentation.sourceName(for: entry.source))
    }

    /// A tinted icon plus its value, matching the account and category chips elsewhere.
    private func factValue(_ title: String, symbolName: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: .circle)

            Text(title)
        }
    }

    private var isLinked: Bool {
        entry.transfer != nil || entry.loan != nil || entry.investmentCashFlow != nil
    }

    private var linkedExplanation: String {
        if entry.transfer != nil {
            return "This entry is one leg of a transfer. Edit or delete it from the transfer's screen."
        }

        if entry.loan != nil {
            return "This entry is linked to a loan. Change it from the loan's screen."
        }

        return "This entry is linked to an investment cash flow. Change it from the investment's screen."
    }

    private func edit() {
        isShowingEditor = true
    }

    private func delete() {
        do {
            try ledgerService.delete(entry)
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
