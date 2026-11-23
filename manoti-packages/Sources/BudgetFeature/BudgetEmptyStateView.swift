//
//  BudgetEmptyStateView.swift
//  BudgetFeature
//

import AppModels
import Modifiers
import SwiftUI

/// The first-run state for a period that has no envelopes yet.
struct BudgetEmptyStateView: View {
    let kind: BudgetPeriodKind
    let onSetUp: () -> Void

    var body: some View {
        VStack(spacing: ManotiSpacing.large) {
            EmptyStateView(
                symbolName: "chart.pie",
                title: "Set up this \(kind.displayName.lowercased())",
                message:
                    "Add a limit for the categories you want to track. Only confirmed expenses count, and you can change the limits at any time."
            )

            Button(action: onSetUp) {
                Label("Set up this period", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.top, ManotiSpacing.large)
    }
}
