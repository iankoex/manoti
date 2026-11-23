//
//  PlanView.swift
//  PlanFeature
//

import AppModels
import AppServices
import BudgetFeature
import InvestmentsFeature
import Modifiers
import SettingsFeature
import SwiftUI
import TransfersFeature

public struct PlanView: View {
    @Environment(AppService.self) private var appService
    @Environment(BudgetService.self) private var budgetService
    @Environment(TransferService.self) private var transferService
    @Environment(PrivacyService.self) private var privacyService

    @State private var budgetSummary: BudgetSummary?
    @State private var budgetSafeToSpend: SafeToSpend?
    @State private var unpairedTransferCount = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                    Text("Budgets, investments and transfers live here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        BudgetView()
                    } label: {
                        BudgetPlanCard(summary: budgetSummary, safeToSpend: budgetSafeToSpend)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SavingsView()
                    } label: {
                        PlanLinkCard(
                            symbolName: "banknote",
                            tint: ManotiColor.forHex("#5856D6"),
                            title: "Savings",
                            message:
                                "Sinking funds for irregular bills and goals tracked against an account.",
                            badge: "Open"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        InvestmentsView()
                    } label: {
                        PlanLinkCard(
                            symbolName: "chart.line.uptrend.xyaxis",
                            tint: ManotiColor.forHex("#27AE60"),
                            title: "Investments",
                            message:
                                "Treasury bonds, bills and money market accounts, with verified coupons and an illustrative what-if.",
                            badge: "Open"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        TransferListView()
                    } label: {
                        PlanLinkCard(
                            symbolName: "arrow.left.arrow.right",
                            tint: ManotiColor.forHex("#2F80ED"),
                            title: "Transfers",
                            message: "Pair the two sides of money moved between your accounts.",
                            badge: unpairedTransferCount == 0 ? "All matched" : "\(unpairedTransferCount) need a match"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, ManotiSpacing.regular)
                .padding(.bottom, 88)
            }
            .background(.background)
            .navigationTitle("Plan")
            .toolbar {
                SettingsToolbarItem()

                ToolbarItem(placement: .primaryAction) {
                    PrivacyToolbarButton(isHidden: privacyService.isAmountsHidden) {
                        togglePrivacy()
                    }
                }
            }
            .onManotiDataChange {
                reloadBudget()
                reloadTransfers()
            }
        }
    }

    private func togglePrivacy() {
        if privacyService.isAmountsHidden {
            privacyService.reveal()
        } else {
            privacyService.hide()
        }
    }

    private func reloadTransfers() {
        unpairedTransferCount = (try? transferService.unpairedLegs().count) ?? 0
    }

    private func reloadBudget() {
        var calendar = Calendar.current
        calendar.firstWeekday = appService.weekStartsOn

        do {
            let period = try budgetService.currentPeriod(
                kind: .month,
                containing: Date.now,
                calendar: calendar
            )
            budgetSummary = try budgetService.summary(
                for: period,
                displayCurrency: appService.displayCurrency
            )
            budgetSafeToSpend = try budgetService.safeToSpend(
                for: period,
                displayCurrency: appService.displayCurrency
            )
        } catch {
            budgetSummary = nil
            budgetSafeToSpend = nil
        }
    }
}

private struct PlanLinkCard: View {
    let symbolName: String
    let tint: Color
    let title: String
    let message: String
    let badge: String

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            HStack(spacing: ManotiSpacing.medium) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)

                Spacer(minLength: 8)

                HStack(spacing: 3) {
                    Text(badge)
                        .font(.caption2.weight(.semibold))

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityHint("Opens \(title.lowercased()).")
    }
}
