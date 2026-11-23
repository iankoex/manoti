//
//  BudgetPlanCard.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// The Plan tab's Budget card: this period's remaining, safe-to-spend and progress.
public struct BudgetPlanCard: View {
    private let summary: BudgetSummary?
    private let safeToSpend: SafeToSpend?

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    public init(summary: BudgetSummary?, safeToSpend: SafeToSpend?) {
        self.summary = summary
        self.safeToSpend = safeToSpend
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            HStack(spacing: ManotiSpacing.medium) {
                Image(systemName: "chart.pie")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ManotiColor.forHex("#2F80ED"))
                    .frame(width: 42, height: 42)
                    .background(ManotiColor.forHex("#2F80ED").opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)

                Text("Budget")
                    .font(.headline)

                Spacer(minLength: 8)

                HStack(spacing: 3) {
                    Text("Open")
                        .font(.caption2.weight(.semibold))

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }

            if let summary, !summary.envelopes.isEmpty {
                HStack(spacing: ManotiSpacing.large) {
                    figure("Remaining", money: summary.remaining)
                    figure("Safe to spend", money: safeToSpend?.amount, colour: .green)
                }

                if amountsHidden {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 8)
                        .accessibilityHidden(true)
                } else {
                    BudgetProgressBar(
                        fraction: BudgetFormatting.progressFraction(
                            spentMinor: summary.totalSpent.minorUnits,
                            limitMinor: summary.totalLimit.minorUnits
                        ),
                        tint: summary.remaining.minorUnits < 0 ? .red : .accentColor
                    )
                }

                Text(BudgetFormatting.envelopeCount(summary.envelopes.count, kind: summary.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Set up envelopes to track this period's spending.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the budget.")
    }

    @ViewBuilder
    private func figure(_ title: String, money: Money?, colour: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if let money {
                MaskedAmountText(
                    money,
                    showsSign: title == "Remaining",
                    style: .subheadline.weight(.semibold),
                    colour: colour
                )
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
