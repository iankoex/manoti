//
//  AmountKeypad.swift
//  Modifiers
//

import SwiftUI

/// The custom amount keypad shared by the Add sheet's expense, income and transfer modes.
public struct AmountKeypad: View {
    private let onPress: (String) -> Void

    public init(onPress: @escaping (String) -> Void) {
        self.onPress = onPress
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        KeypadKey(title: key) {
                            onPress(key)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var rows: [[String]] {
        [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
    }
}

private struct KeypadKey: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .accessibilityLabel(title == "⌫" ? "Delete" : title)
    }
}
