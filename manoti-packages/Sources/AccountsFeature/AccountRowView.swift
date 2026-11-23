//
//  AccountRowView.swift
//  AccountsFeature
//

import AppModels
import Modifiers
import SwiftUI

struct AccountRowView: View {
    let account: Account

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.symbolName)
                .font(.subheadline)
                .foregroundStyle(ManotiColor.forHex(account.colorHex))
                .frame(width: 34, height: 34)
                .background(ManotiColor.forHex(account.colorHex).opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.body.weight(.medium))

                Text("\(account.kind.displayName) · \(account.currency.code)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            AmountText(account.balance, style: .subheadline.weight(.medium))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(account.displayName), balance \(AmountMask.money(account.balance, hidden: amountsHidden))"
        )
    }
}
