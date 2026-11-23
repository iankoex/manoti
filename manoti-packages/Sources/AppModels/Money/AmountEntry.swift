//
//  AmountEntry.swift
//  AppModels
//

import Foundation

/// Shared key handling for the custom numeric keypad.
nonisolated public enum AmountEntry {
    /// Applies one key to an editable major-unit string, allowing one decimal point and at
    /// most two decimal places.
    public static func apply(_ key: String, to text: inout String) {
        if key == "⌫" {
            if !text.isEmpty {
                text.removeLast()
            }
            return
        }

        if key == "." {
            guard !text.contains(".") else {
                return
            }

            text += text.isEmpty ? "0." : "."
            return
        }

        if let dotIndex = text.firstIndex(of: ".") {
            let decimals = text.distance(from: dotIndex, to: text.endIndex) - 1
            guard decimals < 2 else {
                return
            }
        }

        if text == "0" {
            text = key
        } else {
            text += key
        }
    }
}
