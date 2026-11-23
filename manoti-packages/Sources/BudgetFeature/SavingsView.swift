//
//  SavingsView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sinking funds and savings goals, pushed from the Plan tab.
public struct SavingsView: View {
    @Environment(SavingsService.self) private var savingsService

    @State private var funds: [SinkingFund] = []
    @State private var goals: [Goal] = []
    @State private var editor: SavingsEditor?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        List {
            Section {
                if funds.isEmpty {
                    emptyRow(
                        "No sinking funds yet.",
                        detail: "Set money aside for a car service, school fees or a holiday."
                    )
                } else {
                    ForEach(funds) { fund in
                        NavigationLink {
                            SinkingFundDetailView(fund: fund)
                        } label: {
                            SinkingFundRow(fund: fund)
                        }
                    }
                }
            } header: {
                Text("Sinking funds")
            } footer: {
                Text("Contributions are earmarked, not moved out of an account.")
            }

            Section {
                if goals.isEmpty {
                    emptyRow(
                        "No goals yet.",
                        detail: "Track an emergency fund or a big purchase against an account."
                    )
                } else {
                    ForEach(goals) { goal in
                        NavigationLink {
                            GoalDetailView(goal: goal)
                        } label: {
                            GoalRow(goal: goal)
                        }
                    }
                }
            } header: {
                Text("Goals")
            }
        }
        .navigationTitle("Savings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New sinking fund", systemImage: "banknote") {
                        editor = .newFund
                    }
                    Button("New goal", systemImage: "target") {
                        editor = .newGoal
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { target in
            switch target {
                case .newFund:
                    SinkingFundEditorView(fund: nil)
                case .editFund(let fund):
                    SinkingFundEditorView(fund: fund)
                case .newGoal:
                    GoalEditorView(goal: nil)
                case .editGoal(let goal):
                    GoalEditorView(goal: goal)
            }
        }
        .alert(
            "Could not update savings",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onManotiDataChange { reload() }
    }

    private func emptyRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        do {
            funds = try savingsService.fetchFunds()
            goals = try savingsService.fetchGoals()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum SavingsEditor: Identifiable {
    case newFund
    case editFund(SinkingFund)
    case newGoal
    case editGoal(Goal)

    var id: String {
        switch self {
            case .newFund: "new-fund"
            case .editFund(let fund): "fund-\(fund.id)"
            case .newGoal: "new-goal"
            case .editGoal(let goal): "goal-\(goal.id)"
        }
    }
}

private struct SinkingFundRow: View {
    let fund: SinkingFund

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fund.name)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 6) {
                MaskedAmountText(fund.funded, style: .caption, colour: .secondary)
                Text("of")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MaskedAmountText(fund.target, style: .caption, colour: .secondary)
            }

            if let fraction = SavingsFormatting.progressFraction(
                fundedMinor: fund.fundedMinor,
                targetMinor: fund.targetMinor
            ) {
                ProgressView(value: amountsHidden ? 0 : fraction)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct GoalRow: View {
    let goal: Goal

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(goal.name)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 6) {
                MaskedAmountText(
                    Money(minorUnits: goal.progressMinor, currency: goal.currency),
                    style: .caption,
                    colour: .secondary
                )
                Text("of")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MaskedAmountText(goal.target, style: .caption, colour: .secondary)
            }

            if let fraction = SavingsFormatting.progressFraction(
                fundedMinor: goal.progressMinor,
                targetMinor: goal.targetMinor
            ) {
                ProgressView(value: amountsHidden ? 0 : fraction)
                    .tint(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

enum SavingsFormatting {
    static func progressFraction(fundedMinor: Int64, targetMinor: Int64) -> Double? {
        guard targetMinor > 0 else {
            return nil
        }

        return min(1, max(0, Double(fundedMinor) / Double(targetMinor)))
    }
}
