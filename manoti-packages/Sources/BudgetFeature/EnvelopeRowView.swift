//
//  EnvelopeRowView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// One category envelope: spent vs limit, remaining, carried rollover and progress.
struct EnvelopeRowView: View {
    let row: EnvelopeSummary

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack(alignment: .top, spacing: ManotiSpacing.medium) {
                Image(systemName: row.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ManotiColor.forHex(row.colorHex))
                    .frame(width: 34, height: 34)
                    .background(ManotiColor.forHex(row.colorHex).opacity(0.12), in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    categoryLine
                    amountLine
                }

                Spacer(minLength: 8)

                if !row.limit.isZero {
                    VStack(alignment: .trailing, spacing: 2) {
                        MaskedAmountText(
                            row.remaining,
                            showsSign: true,
                            style: .subheadline.weight(.semibold),
                            colour: amountsHidden ? nil : (row.remaining.minorUnits < 0 ? .red : nil)
                        )

                        if !amountsHidden {
                            Text(row.remaining.minorUnits < 0 ? "over" : "left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if row.limit.isZero {
                Text("No limit — excluded from safe to spend")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                progressLine
            }

            if !row.rollover.isZero {
                HStack(spacing: ManotiSpacing.tiny) {
                    Text("Carried in")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    MaskedAmountText(row.rollover, showsSign: true, style: .caption2)
                }
            }

            if !row.missingRates.isEmpty {
                Label(
                    "No rate for \(row.missingRates.joined(separator: ", ")) — shown 1:1",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the envelope editor.")
    }

    private var categoryLine: some View {
        HStack(spacing: ManotiSpacing.small) {
            Text(row.categoryName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if row.isFixed {
                badge("Fixed")
            }

            if row.isArchived {
                badge("Archived")
            }
        }
    }

    /// One text, so a long amount shrinks instead of breaking in the middle of a figure.
    private var amountLine: some View {
        Text(amountSummary)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var amountSummary: String {
        let spent = AmountMask.money(row.spent, hidden: amountsHidden)

        guard !row.limit.isZero else {
            return "\(spent) spent · no limit"
        }

        let limit = AmountMask.money(row.limit, hidden: amountsHidden)
        return "\(spent) of \(limit)"
    }

    @ViewBuilder
    private var progressLine: some View {
        if amountsHidden {
            Capsule()
                .fill(.quaternary)
                .frame(height: 6)
                .accessibilityHidden(true)
        } else {
            HStack(spacing: ManotiSpacing.small) {
                BudgetProgressBar(
                    fraction: BudgetFormatting.progressFraction(
                        spentMinor: row.spent.minorUnits,
                        limitMinor: row.limit.minorUnits
                    ),
                    tint: row.remaining.minorUnits < 0 ? .red : ManotiColor.forHex(row.colorHex)
                )

                if let percentage = BudgetFormatting.percentUsed(
                    spentMinor: row.spent.minorUnits,
                    limitMinor: row.limit.minorUnits
                ) {
                    Text("\(percentage)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(percentage > 100 ? .red : .secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, ManotiSpacing.small)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: .capsule)
    }
}
