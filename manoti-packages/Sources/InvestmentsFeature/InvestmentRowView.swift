//
//  InvestmentRowView.swift
//  InvestmentsFeature
//

import AppModels
import Modifiers
import SwiftUI

struct InvestmentRowView: View {
    let investment: Investment

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        HStack(spacing: ManotiSpacing.medium) {
            Image(systemName: investment.type.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if investment.isPending {
                        badge("Pending", isWarning: true)
                    } else if investment.isMatured {
                        badge("Matured", isWarning: false)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                if let nextCoupon = nextCouponDate {
                    Text("Next coupon \(nextCoupon.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: ManotiSpacing.small)

            VStack(alignment: .trailing, spacing: 2) {
                AmountText(investment.nominal, style: .subheadline.weight(.semibold))

                Text("nominal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .foregroundStyle(investment.isMatured ? .secondary : .primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        if !investment.issueNumber.isEmpty {
            return investment.issueNumber
        }

        return investment.type.displayName
    }

    private var subtitle: String {
        switch investment.type {
            case .treasuryBond:
                return "\(percent(investment.couponRateBasisPoints))% coupon"
            case .treasuryBill:
                let price = Money(minorUnits: investment.cashInvestedMinor, currency: investment.currency)
                return "Paid \(AmountMask.money(price, hidden: amountsHidden))"
            case .moneyMarket:
                return "\(percent(investment.annualRateBasisPoints))% p.a."
        }
    }

    private var nextCouponDate: Date? {
        guard investment.type == .treasuryBond, investment.isActive else {
            return nil
        }

        return InvestmentMath.couponSchedule(for: investment, from: Date.now).first?.date
    }

    private var tint: Color {
        switch investment.type {
            case .treasuryBond: ManotiColor.forHex("#27AE60")
            case .treasuryBill: ManotiColor.forHex("#2F80ED")
            case .moneyMarket: ManotiColor.forHex("#9B51E0")
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            title,
            subtitle,
            "nominal \(AmountMask.money(investment.nominal, hidden: amountsHidden))",
        ]

        if let nextCouponDate {
            parts.append("next coupon \(nextCouponDate.formatted(date: .abbreviated, time: .omitted))")
        }

        if investment.isPending {
            parts.append("pending settlement")
        } else if investment.isMatured {
            parts.append("matured")
        }

        return parts.joined(separator: ", ")
    }

    private func percent(_ basisPoints: Decimal) -> String {
        "\(basisPoints / 100)"
    }

    private func badge(_ text: String, isWarning: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isWarning ? Color.white : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isWarning ? Color.orange : Color.secondary.opacity(0.15),
                in: .capsule
            )
    }
}
