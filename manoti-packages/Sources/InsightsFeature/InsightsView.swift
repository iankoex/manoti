//
//  InsightsView.swift
//  InsightsFeature
//

import AppModels
import AppServices
import Charts
import Modifiers
import SettingsFeature
import SwiftUI

/// The Insights tab: an equal-elapsed comparison of the current month or week with the
/// previous one and with recent history.
public struct InsightsView: View {
    @Environment(InsightsService.self) private var insights
    @Environment(AppService.self) private var appService
    @Environment(PrivacyService.self) private var privacyService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var kind: InsightPeriodKind = .month
    @State private var comparison: SpendComparison?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                    Picker("Comparison period", selection: $kind) {
                        Text("Month").tag(InsightPeriodKind.month)
                        Text("Week").tag(InsightPeriodKind.week)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Comparison period")

                    content
                }
                .padding(.horizontal, ManotiSpacing.regular)
                .padding(.bottom, 88)
            }
            .background(.background)
            .navigationTitle("Insights")
            .toolbar {
                SettingsToolbarItem()

                ToolbarItem(placement: .primaryAction) {
                    PrivacyToolbarButton(isHidden: privacyService.isAmountsHidden) {
                        togglePrivacy()
                    }
                }
            }
            .alert("Could not load insights", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: kind) { _, _ in reload() }
            .onManotiDataChange { reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let comparison {
            if comparison.currentTotal.isZero && comparison.previousTotal.isZero {
                EmptyStateView(
                    symbolName: "chart.bar.xaxis",
                    title: "No spending yet",
                    message:
                        "Log a few expenses and Insights will compare this period with the previous one, using the same number of elapsed days."
                )
                .padding(.top, ManotiSpacing.extraLarge)
            } else {
                dashboard(for: comparison)
            }
        } else if isLoading {
            ProgressView("Comparing periods…")
                .frame(maxWidth: .infinity)
                .padding(.top, ManotiSpacing.extraLarge)
        } else {
            Text("Adjust the period or try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, ManotiSpacing.large)
        }
    }

    private func dashboard(for comparison: SpendComparison) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.large) {
            ComparisonHeroCard(
                comparison: comparison,
                windowText: InsightsFormatting.windowSummary(
                    current: comparison.currentInterval,
                    previous: comparison.previousInterval,
                    kind: comparison.kind,
                    elapsedDays: comparison.elapsedDays,
                    calendar: comparisonCalendar
                )
            )

            FixedVariableCard(comparison: comparison)

            ComparisonChartCard(points: comparison.dailyPoints, kind: comparison.kind)

            if !comparison.categoryDeltas.isEmpty {
                CategoryChangesCard(deltas: comparison.categoryDeltas)
            }

            if !comparison.topMerchants.isEmpty {
                TopMerchantsCard(merchants: comparison.topMerchants)
            }

            if let small = comparison.smallFrequent {
                SmallFrequentCard(small: small)
            }

            if !comparison.balanceDrift.isEmpty {
                BalanceDriftCard(drift: comparison.balanceDrift)
            }

            if !comparison.missingRates.isEmpty {
                Label(
                    "No rate for \(comparison.missingRates.joined(separator: ", ")) — shown 1:1",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
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

    private var comparisonCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = appService.weekStartsOn
        return calendar
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func reload() {
        isLoading = true
        defer { isLoading = false }

        do {
            comparison = try insights.comparison(
                kind: kind,
                containing: Date(),
                displayCurrency: appService.displayCurrency,
                calendar: comparisonCalendar
            )
            errorMessage = nil
        } catch {
            comparison = nil
            errorMessage = "The comparison could not be built. Please try again."
        }
    }
}

// MARK: - Hero

private struct ComparisonHeroCard: View {
    let comparison: SpendComparison
    let windowText: String

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text(headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            AmountText(
                comparison.currentTotal,
                style: .system(size: 38, weight: .semibold, design: .rounded)
            )

            HStack(spacing: ManotiSpacing.small) {
                Text("Previous")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MaskedAmountText(comparison.previousTotal, style: .subheadline.weight(.medium))

                Spacer(minLength: ManotiSpacing.small)

                changeBadge
            }

            Text(windowText)
                .font(.caption)
                .foregroundStyle(.secondary)

            history
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private var headline: String {
        comparison.kind == .month ? "Spent this month" : "Spent this week"
    }

    @ViewBuilder
    private var changeBadge: some View {
        if amountsHidden {
            EmptyView()
        } else if let percent = comparison.percentChange,
            let text = InsightsFormatting.signedPercent(percent)
        {
            Label(text, systemImage: percentSymbol(percent))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(percentColour(percent))
        } else {
            Text("No previous spend")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var history: some View {
        if let average = comparison.trailingAverage {
            HStack(spacing: ManotiSpacing.tiny) {
                Text("Usually")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MaskedAmountText(average, style: .caption.weight(.medium))

                Text("for these days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let message = comparison.insufficientHistoryMessage {
            Text(message)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, ManotiSpacing.small)
                .padding(.vertical, ManotiSpacing.tiny)
                .background(.quaternary, in: .capsule)
        }
    }

    private func percentSymbol(_ percent: Double) -> String {
        if percent > 0 {
            return "arrow.up.right"
        }

        if percent < 0 {
            return "arrow.down.right"
        }

        return "equal"
    }

    private func percentColour(_ percent: Double) -> Color {
        if percent > 0 {
            return ManotiColor.forHex("#EB5757")
        }

        if percent < 0 {
            return ManotiColor.forHex("#27AE60")
        }

        return .secondary
    }
}

// MARK: - Fixed vs variable

private struct FixedVariableCard: View {
    let comparison: SpendComparison

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text("Fixed vs variable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            row("Fixed", money: comparison.fixedCurrent, previous: comparison.fixedPrevious)

            Divider()

            row("Variable", money: comparison.variableCurrent, previous: comparison.variablePrevious)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private func row(_ title: String, money: Money, previous: Money) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                if !amountsHidden,
                    let share = InsightsFormatting.sharePercent(
                        partMinor: money.minorUnits,
                        totalMinor: comparison.currentTotal.minorUnits
                    )
                {
                    Text("\(share) of spending")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: ManotiSpacing.small)

            VStack(alignment: .trailing, spacing: 2) {
                MaskedAmountText(money, style: .subheadline.weight(.semibold))

                HStack(spacing: ManotiSpacing.tiny) {
                    Text("previous")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    MaskedAmountText(previous, style: .caption2)
                }
            }
        }
    }
}

// MARK: - Chart

private struct ComparisonChartCard: View {
    let points: [DailyComparisonPoint]
    let kind: InsightPeriodKind

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text("Spend per day")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if amountsHidden {
                AmountsHiddenPlaceholder("Chart hidden")
                    .frame(height: 150)
            } else {
                chart
                    .frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var currentLabel: String {
        kind == .month ? "This month" : "This week"
    }

    private var previousLabel: String {
        kind == .month ? "Last month" : "Last week"
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", point.dayIndex),
                    y: .value("Spent", chartValue(point.current))
                )
                .foregroundStyle(by: .value("Period", currentLabel))
                .opacity(0.12)

                LineMark(
                    x: .value("Day", point.dayIndex),
                    y: .value("Spent", chartValue(point.current))
                )
                .foregroundStyle(by: .value("Period", currentLabel))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                LineMark(
                    x: .value("Day", point.dayIndex),
                    y: .value("Spent", chartValue(point.previous))
                )
                .foregroundStyle(by: .value("Period", previousLabel))
                .lineStyle(
                    StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 3])
                )
            }
        }
        .chartForegroundStyleScale(
            domain: [currentLabel, previousLabel],
            range: [Color.accentColor, Color.secondary]
        )
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text("Day \(day)")
                    }
                }
            }
        }
        .accessibilityLabel("Daily spending compared with the previous period")
    }

    private func chartValue(_ money: Money) -> Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }
}

// MARK: - Category changes

private struct CategoryChangesCard: View {
    let deltas: [CategorySpendDelta]

    @Environment(\.manotiAmountsHidden) private var amountsHidden
    @State private var isExpanded = false

    private let collapsedLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text("Category changes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(visibleDeltas, id: \.categoryID) { delta in
                row(delta)
            }

            if sortedDeltas.count > collapsedLimit {
                Button {
                    withAnimation(.snappy) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Show less" : "Show all \(sortedDeltas.count) categories")
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var sortedDeltas: [CategorySpendDelta] {
        deltas.sorted { lhs, rhs in
            let leftDifference = abs(lhs.difference.minorUnits)
            let rightDifference = abs(rhs.difference.minorUnits)

            if leftDifference != rightDifference {
                return leftDifference > rightDifference
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var visibleDeltas: [CategorySpendDelta] {
        isExpanded ? sortedDeltas : Array(sortedDeltas.prefix(collapsedLimit))
    }

    private func row(_ delta: CategorySpendDelta) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.medium) {
            Image(systemName: delta.symbolName)
                .font(.subheadline)
                .foregroundStyle(ManotiColor.forHex(delta.colorHex))
                .frame(width: 24)

            Text(delta.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: ManotiSpacing.small)

            VStack(alignment: .trailing, spacing: 2) {
                MaskedAmountText(delta.current, style: .subheadline.weight(.medium))

                HStack(spacing: ManotiSpacing.tiny) {
                    MaskedAmountText(
                        delta.difference,
                        showsSign: true,
                        style: .caption,
                        colour: amountsHidden ? nil : differenceColour(delta.difference)
                    )

                    if !amountsHidden,
                        let percent = InsightsFormatting.signedPercent(delta.percentChange)
                    {
                        Text(percent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func differenceColour(_ difference: Money) -> Color {
        if difference.minorUnits > 0 {
            return ManotiColor.forHex("#EB5757")
        }

        if difference.minorUnits < 0 {
            return ManotiColor.forHex("#27AE60")
        }

        return .secondary
    }
}

// MARK: - Merchants

private struct TopMerchantsCard: View {
    let merchants: [MerchantSpend]

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text("Top merchants")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(merchants) { merchant in
                HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.small) {
                    Text(merchant.payee)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer(minLength: ManotiSpacing.small)

                    Text("\(merchant.count)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    MaskedAmountText(merchant.total, style: .subheadline.weight(.medium))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Small frequent spends

private struct SmallFrequentCard: View {
    let small: SmallFrequentSpends

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text("Small frequent spends")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            summary
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    InsightsFormatting.smallSpendSummary(
                        count: small.count,
                        threshold: small.threshold,
                        total: small.total,
                        hidden: amountsHidden
                    )
                )

            if !small.topPayees.isEmpty {
                Divider()

                ForEach(small.topPayees) { payee in
                    HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.small) {
                        Text(payee.payee)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: ManotiSpacing.small)

                        Text("\(payee.count)×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        MaskedAmountText(payee.total, style: .subheadline.weight(.medium))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var summary: some View {
        HStack(spacing: 0) {
            Text("\(small.count) \(small.count == 1 ? "purchase" : "purchases") ≤ ")
                .font(.subheadline)

            MaskedAmountText(small.threshold, style: .subheadline)

            Text(", ")
                .font(.subheadline)

            MaskedAmountText(small.total, style: .subheadline)

            Text(" total")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Balance drift

private struct BalanceDriftCard: View {
    let drift: [BalanceDrift]

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Label("Balance drift", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(
                "The ledger and the bank's last reported balance disagree. A missing transaction usually explains this."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            ForEach(drift) { row in
                VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                    HStack(spacing: ManotiSpacing.small) {
                        Text(row.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        Spacer(minLength: ManotiSpacing.small)

                        Text(row.asOf.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: ManotiSpacing.medium) {
                        value("Reported", money: row.reportedBalance)
                        value("Ledger", money: row.ledgerBalance)
                        value(
                            "Difference",
                            money: row.difference,
                            showsSign: true,
                            colour: amountsHidden ? nil : .orange
                        )
                    }
                }

                if row.id != drift.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private func value(
        _ title: String,
        money: Money,
        showsSign: Bool = false,
        colour: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            MaskedAmountText(money, showsSign: showsSign, style: .caption.weight(.medium), colour: colour)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
