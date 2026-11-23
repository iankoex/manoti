//
//  MaskedAmountText.swift
//  Modifiers
//

import AppModels
import SwiftUI

/// Renders a monetary value, replacing it with bullets while amounts are hidden.
public struct MaskedAmountText: View {
    private let money: Money
    private let showsSign: Bool
    private let style: Font
    private let colour: Color?

    @Environment(\.manotiAmountsHidden) private var isAmountsHidden

    public init(_ money: Money, showsSign: Bool = false, style: Font = .body, colour: Color? = nil) {
        self.money = money
        self.showsSign = showsSign
        self.style = style
        self.colour = colour
    }

    public var body: some View {
        Text(AmountMask.signedMoney(money, showsSign: showsSign, hidden: isAmountsHidden))
            .font(style)
            .monospacedDigit()
            .foregroundStyle(colour ?? signColour)
    }

    private var signColour: Color {
        guard showsSign, !money.isZero else {
            return .primary
        }

        return money.minorUnits > 0 ? .green : .primary
    }
}
