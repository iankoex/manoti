//
//  AmountsHiddenPlaceholder.swift
//  Modifiers
//

import SwiftUI

/// A chart or block replacement shown while privacy mode hides monetary figures.
public struct AmountsHiddenPlaceholder: View {
    private let message: String

    public init(_ message: String = "Amounts hidden") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: ManotiSpacing.small) {
            Image(systemName: "eye.slash")
                .font(.title3)

            Text(message)
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
