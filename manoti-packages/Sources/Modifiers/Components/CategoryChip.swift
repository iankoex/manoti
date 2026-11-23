//
//  CategoryChip.swift
//  Modifiers
//

import AppModels
import SwiftUI

public struct CategoryChip: View {
    private let category: SpendingCategory
    private let isSelected: Bool

    public init(category: SpendingCategory, isSelected: Bool = false) {
        self.category = category
        self.isSelected = isSelected
    }

    public var body: some View {
        let tint = ManotiColor.forHex(category.colorHex)

        HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .font(.caption2)
                .foregroundStyle(tint)

            Text(category.name)
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(isSelected ? 0.22 : 0.08), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(isSelected ? 1 : 0), lineWidth: 1.5)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
