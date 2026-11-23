//
//  AmountFieldChip.swift
//  Modifiers
//

import SwiftUI

/// A small secondary amount control beside the hero figure, used for the fee and the
/// received amount. Tapping it retargets the custom keypad.
public struct AmountFieldChip: View {
    private let title: String
    private let value: String
    private let currencyCode: String?
    private let isActive: Bool
    private let action: () -> Void

    public init(
        title: String,
        value: String,
        currencyCode: String? = nil,
        isActive: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.currencyCode = currencyCode
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let currencyCode {
                    Text(currencyCode)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(value.isEmpty ? "0.00" : value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isActive ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10),
                in: .rect(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value.isEmpty ? "0.00" : value)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
