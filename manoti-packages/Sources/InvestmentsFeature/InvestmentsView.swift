//
//  InvestmentsView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// The Plan tab’s investment dashboard: verified holdings and an illustrative what-if.
public struct InvestmentsView: View {
    @Environment(AppService.self) private var appService
    @Environment(InvestmentService.self) private var investmentService

    @State private var investments: [Investment] = []
    @State private var summary: InvestmentSummary?
    @State private var formMode: InvestmentFormState.Mode?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                if investments.isEmpty {
                    EmptyStateView(
                        symbolName: "chart.line.uptrend.xyaxis",
                        title: "No investments yet",
                        message:
                            "Track Treasury bonds, bills and money market accounts as assets. Purchases are not spending, and coupons are income net of withholding tax."
                    )
                    .padding(.top, ManotiSpacing.extraLarge)
                }

                DashboardCard(summary: summary)
                VerifiedCashFlowCard(bonds: verifiedBonds, total: verifiedCouponTotal)
                ProjectedValueCard(summary: summary)
                WhatIfCard()

                holdingsSection(title: "Active", investments: activeInvestments)
                holdingsSection(title: "Pending settlement", investments: pendingInvestments)
                holdingsSection(title: "Matured", investments: maturedInvestments)
            }
            .padding(.horizontal, ManotiSpacing.regular)
            .padding(.bottom, 88)
        }
        .background(.background)
        .navigationTitle("Investments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Treasury bond", systemImage: InvestmentType.treasuryBond.symbolName) {
                        formMode = .bond
                    }

                    Button("Treasury bill", systemImage: InvestmentType.treasuryBill.symbolName) {
                        formMode = .bill
                    }

                    Button("Money market", systemImage: InvestmentType.moneyMarket.symbolName) {
                        formMode = .moneyMarket
                    }
                } label: {
                    Label("Add investment", systemImage: "plus")
                }
            }
        }
        .sheet(item: $formMode) { mode in
            switch mode {
                case .bond, .bill:
                    InvestmentFormView(mode: mode)
                case .moneyMarket:
                    MoneyMarketFormView()
            }
        }
        .alert(
            "Could not load investments",
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

    private var activeInvestments: [Investment] {
        investments.filter { $0.status == .active }
    }

    private var pendingInvestments: [Investment] {
        investments.filter { $0.status == .pending }
    }

    private var maturedInvestments: [Investment] {
        investments.filter { $0.status == .matured }
    }

    private var verifiedBonds: [Investment] {
        investments.filter { $0.type == .treasuryBond && !$0.isSoftDeleted && $0.status != .matured }
    }

    /// Exact remaining net coupons from recorded terms, not a projection.
    private var verifiedCouponTotal: Money {
        let currency = CurrencyCatalog.defaultCurrency
        let total = verifiedBonds.reduce(into: Int64(0)) { partial, investment in
            partial += InvestmentMath.totalNetCoupons(for: investment, from: Date.now)
        }
        return Money(minorUnits: total, currency: currency)
    }

    @ViewBuilder
    private func holdingsSection(title: String, investments: [Investment]) -> some View {
        if !investments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, ManotiSpacing.small)

                ForEach(Array(investments.enumerated()), id: \.element.id) { index, investment in
                    NavigationLink {
                        BondDetailView(investment: investment)
                    } label: {
                        InvestmentRowView(investment: investment)
                    }
                    .buttonStyle(.plain)

                    if index < investments.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ManotiSpacing.regular)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
        }
    }

    private func reload() {
        do {
            investments = try investmentService.fetchInvestments(includeMatured: true)
            summary = try investmentService.summary(displayCurrency: appService.displayCurrency)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DashboardCard: View {
    let summary: InvestmentSummary?

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    private let columns = [
        GridItem(.flexible(), spacing: ManotiSpacing.medium),
        GridItem(.flexible(), spacing: ManotiSpacing.medium),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            HStack(spacing: ManotiSpacing.small) {
                Text("Holdings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Verified")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ManotiColor.forHex("#27AE60"))
                    .padding(.horizontal, ManotiSpacing.small)
                    .padding(.vertical, 3)
                    .background(ManotiColor.forHex("#27AE60").opacity(0.12), in: .capsule)
            }

            if let summary {
                LazyVGrid(columns: columns, alignment: .leading, spacing: ManotiSpacing.medium) {
                    Metric(title: "Total nominal", money: summary.totalNominal)
                    Metric(title: "Cash invested", money: summary.cashInvested)
                    Metric(title: "Total net coupons", money: summary.totalNetCoupons)
                }

                Text("Recorded terms and coupon schedules. Verified figures, not projections.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let nextCoupon = summary.nextCoupon {
                    HStack(spacing: ManotiSpacing.small) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(
                                "Next coupon \(nextCoupon.date.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(.caption.weight(.medium))

                            Text("Net \(AmountMask.money(nextCoupon.net, hidden: amountsHidden)) after withholding tax")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !summary.missingRates.isEmpty {
                    Label(
                        "No rate for \(summary.missingRates.joined(separator: ", ")) — shown 1:1",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            } else {
                Text("—")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }
}

private struct Metric: View {
    let title: String
    let money: Money

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            AmountText(money, style: .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VerifiedCashFlowCard: View {
    let bonds: [Investment]
    let total: Money

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            Label {
                Text("Verified cash flow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(ManotiColor.forHex("#27AE60"))
            }

            AmountText(total, style: .title3.weight(.semibold))

            if bonds.isEmpty {
                Text("No holdings yet")
                    .font(.subheadline.weight(.medium))

                Text(
                    "Verified figures appear here when you add a bond. Nothing in this card is projected."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(bonds.sorted { $0.issueNumber < $1.issueNumber }) { bond in
                    HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.small) {
                        Text(bond.issueNumber.isEmpty ? bond.type.displayName : bond.issueNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: ManotiSpacing.small)

                        Text(AmountMask.money(couponTotal(for: bond), hidden: amountsHidden))
                            .font(.caption.monospacedDigit())
                    }
                }

                Text(
                    "Remaining net coupons across \(bonds.count) \(bonds.count == 1 ? "bond" : "bonds"), from each bond's recorded coupon rate, schedule and withholding tax. These are not projections."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private func couponTotal(for bond: Investment) -> Money {
        Money(
            minorUnits: InvestmentMath.totalNetCoupons(for: bond, from: Date.now),
            currency: bond.currency
        )
    }
}

private struct ProjectedValueCard: View {
    let summary: InvestmentSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Label {
                    Text("Projected (illustrative)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text("Not a record")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, ManotiSpacing.small)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: .capsule)
            }

            if let summary {
                AmountText(summary.projectedValue, style: .title3.weight(.semibold))
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(
                "At your configured reinvestment rate, not the bond coupon rate. Assumes a constant rate, no fees or default, and full reinvestment."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.orange.opacity(0.07), in: .rect(cornerRadius: 16))
    }
}

private struct WhatIfCard: View {
    var body: some View {
        NavigationLink {
            InvestmentScenarioView()
        } label: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                HStack {
                    Label("What if I keep buying bonds?", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ManotiColor.forHex("#27AE60"))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(
                    "An illustrative projection, not a record and not financial advice. See a range at 8%, 10% and 12% gross reinvestment."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ManotiSpacing.regular)
            .background(ManotiColor.forHex("#27AE60").opacity(0.08), in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What if I keep buying bonds? Illustrative projection, not a record.")
    }
}
