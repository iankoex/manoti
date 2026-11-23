//
//  AmountMask.swift
//  Modifiers
//

import AppModels
import SwiftUI

/// Shared helpers for replacing monetary figures while privacy mode is on.
public enum AmountMask {
    public static let placeholder = "••••"

    public static func text(_ value: String, hidden: Bool) -> String {
        hidden ? placeholder : value
    }

    public static func money(_ money: Money, hidden: Bool) -> String {
        text(money.formatted(), hidden: hidden)
    }

    public static func signedMoney(_ money: Money, showsSign: Bool, hidden: Bool) -> String {
        text(signed(money, showsSign: showsSign), hidden: hidden)
    }

    static func signed(_ money: Money, showsSign: Bool) -> String {
        guard showsSign, !money.isZero else {
            return money.formatted()
        }

        let prefix = money.minorUnits > 0 ? "+" : "−"
        return "\(prefix)\(money.formattedMagnitude())"
    }
}

private struct ManotiAmountsHiddenKey: EnvironmentKey {
    nonisolated static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the user has chosen to hide monetary figures.
    public var manotiAmountsHidden: Bool {
        get { self[ManotiAmountsHiddenKey.self] }
        set { self[ManotiAmountsHiddenKey.self] = newValue }
    }
}
