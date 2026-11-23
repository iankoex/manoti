//
//  LedgerEntryRowView.swift
//  LedgerFeature
//

import AppModels
import Modifiers
import SwiftUI

public struct LedgerEntryRowView: View {
    private let entry: LedgerEntry

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    public init(entry: LedgerEntry) {
        self.entry = entry
    }

    public var body: some View {
        HStack(spacing: 12) {
            LeadingIcon(entry: entry)

            VStack(alignment: .leading, spacing: 2) {
                Text(LedgerEntryPresentation.title(for: entry))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(entry.occurredAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    if let account = entry.account {
                        Text("·")
                        Text(account.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                AmountText(
                    Money(minorUnits: entry.signedAmountMinor, currency: entry.currency),
                    showsSign: true,
                    style: .subheadline.weight(.medium)
                )

                if entry.feeMinor != 0 {
                    Text("fee \(AmountMask.money(entry.fee, hidden: amountsHidden))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if entry.status == .needsReview {
                    Text("Needs review")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct LeadingIcon: View {
    let entry: LedgerEntry

    var body: some View {
        let tint = LedgerEntryPresentation.tint(for: entry)
        let symbol = LedgerEntryPresentation.symbolName(for: entry)

        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}
