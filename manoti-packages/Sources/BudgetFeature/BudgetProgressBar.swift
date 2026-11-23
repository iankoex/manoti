//
//  BudgetProgressBar.swift
//  BudgetFeature
//

import SwiftUI

/// A thin progress bar with an optional pacing marker.
///
/// The bar is purely visual, so callers hide it entirely while amounts are private.
struct BudgetProgressBar: View {
    let fraction: Double
    var markerFraction: Double?
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * clamped(fraction))

                if let markerFraction {
                    Rectangle()
                        .fill(.primary.opacity(0.35))
                        .frame(width: 2)
                        .offset(x: max(0, proxy.size.width * clamped(markerFraction) - 1))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
