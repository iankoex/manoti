//
//  GoalDetailView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// One savings goal, with progress derived from its linked account.
struct GoalDetailView: View {
    let goal: Goal

    @Environment(\.dismiss) private var dismiss
    @Environment(SavingsService.self) private var savingsService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var isEditing = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.name)
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MaskedAmountText(
                            Money(minorUnits: goal.progressMinor, currency: goal.currency),
                            style: .title2.weight(.semibold)
                        )
                        Text("of")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MaskedAmountText(goal.target, style: .subheadline)
                    }

                    if let fraction = SavingsFormatting.progressFraction(
                        fundedMinor: goal.progressMinor,
                        targetMinor: goal.targetMinor
                    ) {
                        ProgressView(value: amountsHidden ? 0 : fraction)
                            .tint(.green)
                    } else {
                        Text("Set a target to show progress.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                if let targetDate = goal.targetDate {
                    LabeledContent("Target date") {
                        Text(targetDate, format: .dateTime.day().month(.abbreviated).year())
                    }
                }

                if let account = goal.account {
                    LabeledContent("Account", value: account.displayName)
                } else {
                    Text("Link an account to track progress from its balance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !goal.note.isEmpty {
                    LabeledContent("Note") {
                        Text(goal.note)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle("Goal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit goal", systemImage: "pencil") {
                        isEditing = true
                    }

                    Button(goal.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                        setArchived(!goal.isArchived)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            GoalEditorView(goal: goal)
        }
        .alert(
            "Could not update the goal",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func setArchived(_ archived: Bool) {
        do {
            try savingsService.updateGoal(
                goal,
                name: goal.name,
                targetMinor: goal.targetMinor,
                targetDate: goal.targetDate,
                currencyCode: goal.currencyCode,
                account: goal.account,
                note: goal.note,
                isArchived: archived
            )

            if archived {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
