//
//  TransferListView.swift
//  TransfersFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Reviews the two sides of money moved between the user's own accounts.
///
/// Plan pushes this screen, so it deliberately has no navigation stack of its own.
public struct TransferListView: View {
    @Environment(TransferService.self) private var transferService

    @State private var unpairedLegs: [LedgerEntry] = []
    @State private var linkedTransfers: [Transfer] = []
    @State private var pairingLeg: LedgerEntry?
    @State private var unlinkTarget: Transfer?
    @State private var deleteTarget: Transfer?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        Group {
            if unpairedLegs.isEmpty && linkedTransfers.isEmpty {
                EmptyStateView(
                    symbolName: "arrow.left.arrow.right",
                    title: "No transfers to pair",
                    message:
                        "When a bank or mobile money message records one side of a move between your accounts, it waits here until the other side arrives."
                )
            } else {
                List {
                    if !unpairedLegs.isEmpty {
                        Section {
                            ForEach(unpairedLegs) { leg in
                                UnpairedLegRow(leg: leg) {
                                    pairingLeg = leg
                                }
                            }
                        } header: {
                            Text("Needs a match")
                        } footer: {
                            Text(
                                "Each entry is one side of a transfer. Pair it with the matching entry from the other account."
                            )
                        }
                    }

                    if !linkedTransfers.isEmpty {
                        Section("Linked") {
                            ForEach(linkedTransfers) { transfer in
                                LinkedTransferRow(transfer: transfer)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("Unlink", systemImage: "link.badge.minus", role: .destructive) {
                                            unlinkTarget = transfer
                                        }
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            deleteTarget = transfer
                                        }
                                    }
                                    .contextMenu {
                                        Button("Unlink", systemImage: "link.badge.minus", role: .destructive) {
                                            unlinkTarget = transfer
                                        }
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            deleteTarget = transfer
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transfers")
        .sheet(item: $pairingLeg) { leg in
            TransferPairingView(leg: leg)
        }
        .confirmationDialog(
            "Unlink this transfer?",
            isPresented: Binding(
                get: { unlinkTarget != nil },
                set: { if !$0 { unlinkTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unlink", role: .destructive) {
                if let transfer = unlinkTarget {
                    unlink(transfer)
                }
            }
            Button("Cancel", role: .cancel) {
                unlinkTarget = nil
            }
        } message: {
            Text("The two entries stay in their accounts. Only the grouping between them is removed.")
        }
        .confirmationDialog(
            "Delete this transfer?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete both entries", role: .destructive) {
                if let transfer = deleteTarget {
                    delete(transfer)
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("Both sides are removed from their account balances. The rows stay recoverable.")
        }
        .alert(
            "Could not update transfers",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onManotiDataChange { reload() }
    }

    private func reload() {
        do {
            unpairedLegs = try transferService.unpairedLegs()
            linkedTransfers = try transferService.linkedTransfers()
        } catch {
            unpairedLegs = []
            linkedTransfers = []
            errorMessage = error.localizedDescription
        }
    }

    private func unlink(_ transfer: Transfer) {
        do {
            try transferService.unlink(transfer)
            unlinkTarget = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ transfer: Transfer) {
        do {
            try transferService.delete(transfer)
            deleteTarget = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UnpairedLegRow: View {
    let leg: LedgerEntry
    let findMatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: leg.kind == .transferOut ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                .font(.title3)
                .foregroundStyle(leg.kind == .transferOut ? .orange : .green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(leg.account?.displayName ?? "No account")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(leg.kind == .transferOut ? "Out" : "In")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }

                Text(leg.occurredAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if leg.status == .needsReview {
                    Text("Needs review")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                MaskedAmountText(leg.amount, style: .subheadline.weight(.semibold))

                Button("Find match", action: findMatch)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

private struct LinkedTransferRow: View {
    let transfer: Transfer

    var body: some View {
        if let outLeg = transfer.outTransaction, let inLeg = transfer.inTransaction {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(outLeg.account?.displayName ?? "Out") → \(inLeg.account?.displayName ?? "In")")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(transfer.occurredAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text("Out")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MaskedAmountText(outLeg.amount, style: .caption)

                    if outLeg.currency != inLeg.currency {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text("In")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MaskedAmountText(inLeg.amount, style: .caption)
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }
}
