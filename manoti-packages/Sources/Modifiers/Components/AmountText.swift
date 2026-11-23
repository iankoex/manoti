//
//  AmountText.swift
//  Modifiers
//

import AppModels
import SwiftUI

public struct AmountText: View {
    private let money: Money
    private let showsSign: Bool
    private let style: Font

    public init(_ money: Money, showsSign: Bool = false, style: Font = .body) {
        self.money = money
        self.showsSign = showsSign
        self.style = style
    }

    public var body: some View {
        MaskedAmountText(money, showsSign: showsSign, style: style)
    }
}
