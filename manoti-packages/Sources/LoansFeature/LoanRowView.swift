//
//  LoanRowView.swift
//  LoansFeature
//

import AppModels
import Modifiers
import SwiftUI

struct LoanRowView: View {
    let loan: Loan

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        HStack(spacing: ManotiSpacing.medium) {
            Image(systemName: loan.direction.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(loan.counterparty)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if isOverdue {
                        badge("Overdue", isWarning: true)
                    } else if loan.status == .settled {
                        badge("Settled", isWarning: false)
                    }
                }

                Text("\(rowDirectionLabel) · \(loan.startedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text("Original \(AmountMask.money(principal, hidden: amountsHidden))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ManotiSpacing.small)

            VStack(alignment: .trailing, spacing: 2) {
                AmountText(loan.outstanding, style: .subheadline.weight(.semibold))

                Text("outstanding")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .foregroundStyle(loan.status == .settled ? .secondary : .primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var tint: Color {
        switch loan.direction {
            case .lent: ManotiColor.forHex("#27AE60")
            case .borrowed: ManotiColor.forHex("#EB5757")
        }
    }

    private var principal: Money {
        Money(minorUnits: loan.principalMinor, currency: loan.currency)
    }

    private var directionLabel: String {
        switch loan.direction {
            case .lent: "Owed to me"
            case .borrowed: "I owe"
        }
    }

    private var rowDirectionLabel: String {
        switch loan.direction {
            case .lent: "Lent"
            case .borrowed: "Borrowed"
        }
    }

    private var isOverdue: Bool {
        guard loan.status == .open, loan.outstandingMinor > 0, let dueAt = loan.dueAt else {
            return false
        }

        let calendar = Calendar.current
        return calendar.startOfDay(for: dueAt) < calendar.startOfDay(for: Date.now)
    }

    private var accessibilityLabel: String {
        var parts = [
            loan.counterparty,
            "\(directionLabel), outstanding \(AmountMask.money(loan.outstanding, hidden: amountsHidden))",
            "original \(AmountMask.money(principal, hidden: amountsHidden))",
        ]

        if isOverdue {
            parts.append("overdue")
        } else if loan.status == .settled {
            parts.append("settled")
        }

        return parts.joined(separator: ", ")
    }

    private func badge(_ text: String, isWarning: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isWarning ? Color.white : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isWarning ? Color.red : Color.secondary.opacity(0.15),
                in: .capsule
            )
    }
}
