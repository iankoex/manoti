//
//  AccountChip.swift
//  Modifiers
//

import AppModels
import SwiftUI

public struct AccountChip: View {
    private let account: Account
    private let balance: Money
    private let isSelected: Bool
    private let showsBalance: Bool

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    public init(
        account: Account,
        balance: Money? = nil,
        isSelected: Bool = false,
        showsBalance: Bool = true
    ) {
        self.account = account
        self.balance = balance ?? account.balance
        self.isSelected = isSelected
        self.showsBalance = showsBalance
    }

    public var body: some View {
        let tint = ManotiColor.forHex(account.colorHex)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: account.symbolName)
                    .font(.caption)
                    .foregroundStyle(tint)

                Text(account.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            if showsBalance {
                MaskedAmountText(balance, style: .caption, colour: .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(isSelected ? 0.22 : 0.10), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(isSelected ? 1 : 0), lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(account.displayName), \(AmountMask.money(balance, hidden: amountsHidden))"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
