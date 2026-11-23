//
//  TransferPairingView.swift
//  TransfersFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Picks the opposite leg for one unpaired transfer entry.
///
/// Presented as a sheet, so it owns a navigation stack. Every amount uses the shared masked
/// text component; accounts, dates and match reasons stay legible.
public struct TransferPairingView: View {
    private let leg: LedgerEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(TransferService.self) private var transferService

    @State private var candidates: [TransferLinkCandidate] = []
    @State private var errorMessage: String?

    public init(leg: LedgerEntry) {
        self.leg = leg
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Selected entry") {
                    SelectedLegRow(leg: leg)
                }

                if candidates.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
                            Label("No second leg yet", systemImage: "clock.arrow.circlepath")
                                .font(.headline)

                            Text("Wait for the other bank message, or record it manually.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                                RequirementRow("The opposite direction (out pairs with in).")
                                RequirementRow("A different account.")
                                RequirementRow("Within 15 minutes, or a matching reference.")
                                RequirementRow("The same currency for an amount match.")
                            }
                            .padding(.top, ManotiSpacing.small)
                        }
                        .padding(.vertical, ManotiSpacing.small)
                    }
                } else {
                    Section("Possible matches") {
                        ForEach(candidates) { candidate in
                            CandidateRow(candidate: candidate) {
                                link(candidate.entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find a match")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
            .alert(
                "Could not link transfer",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { reload() }
        }
    }

    private func reload() {
        do {
            candidates = try transferService.linkCandidates(for: leg)
        } catch {
            candidates = []
            errorMessage = error.localizedDescription
        }
    }

    private func link(_ candidate: LedgerEntry) {
        do {
            if leg.kind == .transferOut {
                try transferService.link(outLeg: leg, inLeg: candidate)
            } else {
                try transferService.link(outLeg: candidate, inLeg: leg)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SelectedLegRow: View {
    let leg: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: leg.kind == .transferOut ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                .font(.title3)
                .foregroundStyle(leg.kind == .transferOut ? .orange : .green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(leg.account?.displayName ?? "No account")
                    .font(.subheadline.weight(.medium))

                Text(leg.occurredAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            MaskedAmountText(leg.amount, style: .subheadline.weight(.semibold))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct CandidateRow: View {
    let candidate: TransferLinkCandidate
    let link: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.entry.account?.displayName ?? "No account")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(
                    candidate.entry.occurredAt,
                    format: .dateTime.day().month(.abbreviated).year().hour().minute()
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(reasonText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(candidate.reason == .reference ? .green : .orange)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                MaskedAmountText(candidate.entry.amount, style: .subheadline.weight(.medium))

                Button("Link", action: link)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var reasonText: String {
        switch candidate.reason {
            case .reference:
                return "Reference match"
            case .amountAndTime:
                return "Amount and time"
        }
    }
}

private struct RequirementRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: ManotiSpacing.small) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
