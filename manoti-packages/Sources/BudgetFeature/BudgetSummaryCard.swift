//
//  BudgetSummaryCard.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Total budget vs actual, safe-to-spend, pacing and the fixed/variable split.
struct BudgetSummaryCard: View {
    let summary: BudgetSummary
    let safeToSpend: SafeToSpend?

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    private let columns = [
        GridItem(.flexible(), spacing: ManotiSpacing.medium, alignment: .leading),
        GridItem(.flexible(), spacing: ManotiSpacing.medium, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            header
            metrics
            pacing
            Divider()
            split
            extras
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private var header: some View {
        HStack(spacing: ManotiSpacing.small) {
            Text(summary.kind == .month ? "Monthly budget" : "Weekly budget")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Day \(max(1, summary.elapsedDays)) of \(summary.totalDays)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: ManotiSpacing.medium) {
            metric("Total limit", money: summary.totalLimit)
            metric(
                "Spent",
                money: summary.totalSpent,
                colour: summary.remaining.minorUnits < 0 && !amountsHidden ? .red : nil
            )
            metric(
                "Remaining",
                money: summary.remaining,
                showsSign: true,
                colour: summary.remaining.minorUnits < 0 && !amountsHidden ? .red : nil
            )
            metric(
                "Safe to spend today",
                money: safeToSpend?.amount ?? Money.zero(in: summary.currency),
                colour: .green
            )
        }
    }

    private var pacing: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack(spacing: ManotiSpacing.small) {
                Text("Pacing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                pacingValue
            }

            if amountsHidden {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 8)
                    .accessibilityHidden(true)

                Label("Amounts hidden", systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                BudgetProgressBar(
                    fraction: BudgetFormatting.progressFraction(
                        spentMinor: summary.totalSpent.minorUnits,
                        limitMinor: summary.totalLimit.minorUnits
                    ),
                    markerFraction: BudgetFormatting.pacingFraction(
                        totalDays: summary.totalDays,
                        elapsedDays: summary.elapsedDays
                    ),
                    tint: summary.remaining.minorUnits < 0 ? .red : .accentColor
                )

                HStack(spacing: ManotiSpacing.small) {
                    Text("Projected spend")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    MaskedAmountText(summary.projectedSpend, style: .caption2)

                    Spacer()

                    if let safeToSpend {
                        Text("\(safeToSpend.daysRemaining) days left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pacingValue: some View {
        if amountsHidden {
            Text("Hidden")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if let percentage = BudgetFormatting.percentUsed(
            spentMinor: summary.totalSpent.minorUnits,
            limitMinor: summary.totalLimit.minorUnits
        ) {
            Text("\(percentage)% used")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(percentage > 100 ? .red : .secondary)
                .monospacedDigit()
        } else {
            Text("No limit set")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var split: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            splitRow(title: "Fixed", spent: summary.fixedSpent, limit: summary.fixedLimit)
            splitRow(title: "Variable", spent: summary.variableSpent, limit: summary.variableLimit)

            Text("Safe to spend excludes fixed costs and only counts envelopes with a limit.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var extras: some View {
        if !summary.unbudgeted.isZero {
            HStack(spacing: ManotiSpacing.small) {
                Label("Unbudgeted spending", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                MaskedAmountText(summary.unbudgeted, style: .caption.weight(.medium))
            }
        }

        if !summary.rollover.isZero {
            HStack(spacing: ManotiSpacing.small) {
                Text("Rollover included")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                MaskedAmountText(summary.rollover, showsSign: true, style: .caption.weight(.medium))
            }
        }

        if !summary.missingRates.isEmpty {
            Label(
                "No rate for \(summary.missingRates.joined(separator: ", ")) — shown 1:1",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption2)
            .foregroundStyle(.orange)
        }
    }

    private func metric(
        _ title: String,
        money: Money,
        showsSign: Bool = false,
        colour: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            MaskedAmountText(money, showsSign: showsSign, style: .headline, colour: colour)
        }
    }

    private func splitRow(title: String, spent: Money, limit: Money) -> some View {
        HStack(spacing: ManotiSpacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            MaskedAmountText(spent, style: .caption.weight(.medium))
            Text("of")
                .font(.caption2)
                .foregroundStyle(.secondary)
            MaskedAmountText(limit, style: .caption)
        }
    }
}
