//
//  LedgerEntryRowView.swift
//  LedgerFeature
//

import AppModels
import Modifiers
import SwiftUI

public enum LedgerEntryRowDateStyle: Sendable {
    case dateAndTime
    case time
}

public struct LedgerEntryRowView: View {
    private let entry: LedgerEntry
    private let dateStyle: LedgerEntryRowDateStyle

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    public init(entry: LedgerEntry, dateStyle: LedgerEntryRowDateStyle = .dateAndTime) {
        self.entry = entry
        self.dateStyle = dateStyle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LeadingIcon(entry: entry)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LedgerEntryPresentation.title(for: entry))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    AmountText(
                        Money(minorUnits: entry.signedAmountMinor, currency: entry.currency),
                        showsSign: true,
                        style: .subheadline.weight(.medium)
                    )
                    .lineLimit(1)
                    .layoutPriority(1)
                }

                subtitle
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Date and account on the left, fee and review status on the trailing side. Moving the
    /// amount onto the title line gives this row the full width it needs.
    private var subtitle: some View {
        HStack(spacing: 5) {
            occurredAt

            if let account = entry.account {
                separator
                accountLabel(account)
                    .layoutPriority(2)
            }

            if let category = entry.category, !entry.payee.isEmpty {
                separator
                categoryLabel(category)
            }

            Spacer(minLength: 4)

            if entry.feeMinor != 0 {
                Text("fee \(AmountMask.money(entry.fee, hidden: amountsHidden))")
                    .layoutPriority(1)
            }

            if entry.status == .needsReview {
                Text("Needs review")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .layoutPriority(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    /// Grouped lists already show the day in their section header, so only the time repeats.
    private var occurredAt: some View {
        Group {
            switch dateStyle {
                case .dateAndTime:
                    Text(entry.occurredAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                case .time:
                    Text(entry.occurredAt, format: .dateTime.hour().minute())
            }
        }
        .layoutPriority(3)
    }

    private func accountLabel(_ account: Account) -> some View {
        HStack(spacing: 3) {
            Image(systemName: account.symbolName)
                .font(.caption2)
                .foregroundStyle(ManotiColor.forHex(account.colorHex))

            Text(account.displayName)
                .lineLimit(1)
        }
    }

    private func categoryLabel(_ category: SpendingCategory) -> some View {
        let tint = ManotiColor.forHex(category.colorHex)

        return HStack(spacing: 3) {
            Image(systemName: category.symbolName)
                .font(.caption2)

            Text(category.name)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(tint.opacity(0.12), in: .capsule)
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
