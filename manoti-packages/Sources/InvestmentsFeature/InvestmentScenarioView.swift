//
//  InvestmentScenarioView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Charts
import Modifiers
import SwiftUI

/// Illustrative “what if I keep buying bonds?” projection.
///
/// Nothing on this screen writes records. Every value is labelled as a projection, the
/// sensitivity band runs at 8%, 10% and 12% gross, and the default policy keeps purchases
/// capped at the contribution.
public struct InvestmentScenarioView: View {
    @Environment(AppService.self) private var appService
    @Environment(InvestmentService.self) private var investmentService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var amountMinor = Double(InvestmentScenario.defaultAmountMinor)
    @State private var cadenceMonths = 2
    @State private var grossRatePercent = 12.0
    @State private var startDate = InvestmentScenario.defaultStartDate()
    @State private var includeExisting = true
    @State private var useCouponsFirst = true
    @State private var policy: ScenarioPolicy = .capped
    @State private var selectedYear = 2040
    @State private var sensitivityScenario = true

    @State private var includeCapped: [InvestmentScenarioResult] = []
    @State private var freshCapped: [InvestmentScenarioResult] = []
    @State private var includeExcess: [InvestmentScenarioResult] = []
    @State private var freshExcess: [InvestmentScenarioResult] = []
    @State private var existingInvestments: [Investment] = []
    @State private var isCalculating = true
    @State private var errorMessage: String?
    @State private var refreshToken = 0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                disclaimer
                controls
                projectedValues
                if useCouponsFirst {
                    policyComparison
                }
                planSummary
                chartCard
                sensitivityCard
                verifiedInputs
                assumptions
            }
            .padding(.horizontal, ManotiSpacing.regular)
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
        .background(.background)
        .navigationTitle("What if?")
        .overlay(alignment: .topTrailing) {
            if isCalculating {
                ProgressView()
                    .padding(ManotiSpacing.regular)
            }
        }
        .onManotiDataChange { refreshToken += 1 }
        .onChange(of: useCouponsFirst) { _, isOn in
            if !isOn {
                policy = .capped
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
        .task(id: settings) {
            await calculate(settings)
        }
    }

    // MARK: - Header

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Label("Projection only", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                Spacer()

                Text("No records are written")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(InvestmentScenario.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text("Your contribution plan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(
                "Starting \(startDate.formatted(date: .abbreviated, time: .omitted)) · every \(cadenceMonths) \(cadenceMonths == 1 ? "month" : "months")"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: ManotiSpacing.tiny) {
                HStack {
                    Text("Amount")
                        .font(.subheadline)

                    Spacer()

                    AmountText(
                        Money(minorUnits: Int64(amountMinor), currency: CurrencyCatalog.defaultCurrency),
                        style: .subheadline.weight(.semibold)
                    )
                }

                Slider(
                    value: $amountMinor,
                    in: Double(
                        InvestmentScenario.amountLowerBoundMinor)...Double(
                            InvestmentScenario.amountUpperBoundMinor),
                    step: Double(InvestmentScenario.amountStepMinor)
                ) {
                    Text("Contribution amount")
                }
                .accessibilityValue(
                    amountsHidden
                        ? "Amounts hidden"
                        : Money(minorUnits: Int64(amountMinor), currency: CurrencyCatalog.defaultCurrency).formatted()
                )

                HStack {
                    Text(
                        AmountMask.money(
                            Money(
                                minorUnits: InvestmentScenario.amountLowerBoundMinor,
                                currency: CurrencyCatalog.defaultCurrency
                            ),
                            hidden: amountsHidden
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        AmountMask.money(
                            Money(
                                minorUnits: InvestmentScenario.amountUpperBoundMinor,
                                currency: CurrencyCatalog.defaultCurrency
                            ),
                            hidden: amountsHidden
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Picker("Cadence", selection: $cadenceMonths) {
                ForEach(InvestmentScenario.cadenceOptions, id: \.self) { months in
                    Text(months == 1 ? "Monthly" : "\(months) months")
                        .tag(months)
                        .accessibilityLabel(months == 1 ? "Every month" : "Every \(months) months")
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: ManotiSpacing.tiny) {
                HStack {
                    Text("Gross reinvestment rate")
                        .font(.subheadline)

                    Spacer()

                    Text("\(percent(Int(grossRatePercent * 100)))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                Slider(
                    value: $grossRatePercent,
                    in: 8...15,
                    step: 0.5
                ) {
                    Text("Gross reinvestment rate")
                }

                HStack {
                    Text("8%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("15%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Net \(percent(Int(grossRatePercent * 100) * (10_000 - withholdingTaxBasisPoints) / 10_000))% after \(withholdingTaxBasisPoints / 100)% withholding tax. This is a projection, not a promise."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Include the bonds I already have", isOn: $includeExisting)

            Text(
                includeExisting
                    ? "Existing bonds add their actual coupons, maturities and face value to the ladder."
                    : "Start fresh means zero existing bonds and zero starting cash. Your contributions still apply."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Toggle("Use coupons first", isOn: $useCouponsFirst)

            Text(
                useCouponsFirst
                    ? "Coupons fund each purchase before new cash."
                    : "Every purchase is new cash; coupons accumulate as unused cash."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: ManotiSpacing.tiny) {
                Text("Coupon policy")
                    .font(.subheadline)

                Picker("Coupon policy", selection: $policy) {
                    ForEach(ScenarioPolicy.allCases) { policy in
                        Text(policy.shortLabel).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!useCouponsFirst)

                Text(policy.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    // MARK: - Checkpoints

    private var projectedValues: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            HStack {
                Text("Projected value")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(policy.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Highlighted values use \(rateLabel) gross / \(percent(netRateBasisPoints))% net.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: ManotiSpacing.small) {
                ForEach(InvestmentScenario.defaultCheckpoints, id: \.self) { year in
                    Button {
                        selectedYear = year
                    } label: {
                        Text(String(year))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, ManotiSpacing.medium)
                            .padding(.vertical, 6)
                            .background(
                                year == selectedYear
                                    ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1),
                                in: .capsule
                            )
                            .foregroundStyle(year == selectedYear ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(year == selectedYear ? .isSelected : [])
                }

                Spacer()
            }

            HStack(spacing: ManotiSpacing.small) {
                Text("Scenario")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Range")
                    .monospacedDigit()
                Text(rateLabel)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(InvestmentScenario.defaultCheckpoints, id: \.self) { year in
                VStack(alignment: .leading, spacing: ManotiSpacing.tiny) {
                    HStack {
                        Text(String(year))
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        if year == selectedYear {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }

                    if let band = band(includeResults, year: year) {
                        CheckpointBandRow(
                            title: "With existing bonds",
                            band: band,
                            atRate: atRateValue(includeResults, year: year),
                            rateLabel: rateLabel
                        )
                    }

                    if let band = band(freshResults, year: year) {
                        CheckpointBandRow(
                            title: "Start fresh",
                            band: band,
                            atRate: atRateValue(freshResults, year: year),
                            rateLabel: rateLabel
                        )
                    }
                }
                .padding(ManotiSpacing.small)
                .background(
                    year == selectedYear ? Color.accentColor.opacity(0.06) : Color.clear,
                    in: .rect(cornerRadius: 10)
                )
            }

            Text(
                "The range covers 8%, 10% and 12% gross reinvestment (7.2%, 9.0% and 10.8% net), plus your slider rate when it differs. The highlighted value uses your current rate."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var policyComparison: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            Text("Both policies at 2060")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .trailing, horizontalSpacing: ManotiSpacing.small, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("With existing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Start fresh")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                policyRow("Capped at \(contributionLabel)", results: includeCapped, fresh: freshCapped)
                policyRow("Reinvest all coupons", results: includeExcess, fresh: freshExcess)
            }

            Text(
                "The capped plan is the default and stays at \(contributionLabel). Reinvest-all is the higher, less conservative case."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private func policyRow(
        _ title: String,
        results: [InvestmentScenarioResult],
        fresh: [InvestmentScenarioResult]
    ) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)

            Text(policyValue(results))
                .font(.caption.weight(.medium))
                .monospacedDigit()

            Text(policyValue(fresh))
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }

    private func policyValue(_ results: [InvestmentScenarioResult]) -> String {
        guard let checkpoint = result(results)?.checkpoint(for: 2060) else {
            return "—"
        }

        return AmountMask.text(compact(checkpoint.totalValue), hidden: amountsHidden)
    }

    private var contributionLabel: String {
        AmountMask.money(
            Money(minorUnits: Int64(amountMinor), currency: CurrencyCatalog.defaultCurrency),
            hidden: amountsHidden
        )
    }

    private var planSummary: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Text("Plan mechanics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(percent(rateBasisPoints))% gross · \(percent(netRateBasisPoints))% net")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: ManotiSpacing.medium, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("With existing")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Start fresh")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                summaryRow("New cash from you", include: currentInclude, fresh: currentFresh) {
                    $0.totalNewCash
                }
                summaryRow("Coupon-funded purchases", include: currentInclude, fresh: currentFresh) {
                    $0.couponFundedPurchases
                }
                summaryRow("Total purchases", include: currentInclude, fresh: currentFresh) {
                    $0.totalPurchases
                }
                summaryRow("Coupons received", include: currentInclude, fresh: currentFresh) {
                    $0.totalCouponsReceived
                }

                GridRow {
                    Text("Self-funding")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selfFundingLabel(currentInclude))
                        .font(.caption.weight(.medium))
                    Text(selfFundingLabel(currentFresh))
                        .font(.caption.weight(.medium))
                }

                summaryRow("Unused coupon cash", include: currentInclude, fresh: currentFresh) {
                    $0.unusedCouponCash
                }
            }

            Text(
                "Self-funding is the year of the last cash top-up. From then on, coupons fund the plan."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private func summaryRow(
        _ title: String,
        include: InvestmentScenarioResult?,
        fresh: InvestmentScenarioResult?,
        value: (InvestmentScenarioResult) -> Money
    ) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let include {
                Text(AmountMask.text(compact(value(include)), hidden: amountsHidden))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }

            if let fresh {
                Text(AmountMask.text(compact(value(fresh)), hidden: amountsHidden))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Text("Contributions vs projected value")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(includeExisting ? "With existing" : "Start fresh")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if amountsHidden {
                AmountsHiddenPlaceholder()
                    .frame(height: 220)
            } else if chartPoints.isEmpty {
                Text("Adjust the plan to see the projection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(chartPoints) { point in
                        AreaMark(
                            x: .value("Year", point.year),
                            yStart: .value("Low", point.low),
                            yEnd: .value("High", point.high)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.12))

                        LineMark(
                            x: .value("Year", point.year),
                            y: .value("Projected value", point.value)
                        )
                        .foregroundStyle(by: .value("Series", "Projected value"))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        LineMark(
                            x: .value("Year", point.year),
                            y: .value("Your cash", point.contributions)
                        )
                        .foregroundStyle(by: .value("Series", "Your cash"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }

                    if let selectedPoint {
                        PointMark(
                            x: .value("Year", selectedPoint.year),
                            y: .value("Projected value", selectedPoint.value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(60)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(compact(Double(amount)))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 220)
                .accessibilityLabel(
                    "Projected value and your cash contributions from \(firstChartYear) to \(lastChartYear). The shaded band shows the 8% to 12% rate range."
                )
            }

            Text(
                "The band is the 8%–12% sensitivity range for this policy. Your cash line is the external money you would put in, not the total invested."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    // MARK: - Sensitivity

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Text("Sensitivity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Gross → net")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Picker("Sensitivity scenario", selection: $sensitivityScenario) {
                Text("With existing").tag(true)
                Text("Start fresh").tag(false)
            }
            .pickerStyle(.segmented)

            Grid(alignment: .trailing, horizontalSpacing: ManotiSpacing.small, verticalSpacing: 6) {
                GridRow {
                    Text("Rate")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)

                    ForEach(InvestmentScenario.defaultCheckpoints, id: \.self) { year in
                        Text(String(year))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(InvestmentScenario.sensitivityGrossRatesBasisPoints, id: \.self) { rate in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(percent(rate))%")
                                .font(.caption.weight(.medium))
                            Text("\(percent(rate * (10_000 - withholdingTaxBasisPoints) / 10_000))% net")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .gridColumnAlignment(.leading)

                        ForEach(InvestmentScenario.defaultCheckpoints, id: \.self) { year in
                            Text(valueLabel(sensitivityResults, rate: rate, year: year))
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                }

                if !InvestmentScenario.sensitivityGrossRatesBasisPoints.contains(rateBasisPoints) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Your rate")
                                .font(.caption.weight(.semibold))
                            Text("\(percent(rateBasisPoints))% · \(percent(netRateBasisPoints))% net")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .gridColumnAlignment(.leading)

                        ForEach(InvestmentScenario.defaultCheckpoints, id: \.self) { year in
                            Text(valueLabel(sensitivityResults, rate: rateBasisPoints, year: year))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Text(
                "Every projected value is illustrative. A lower rate is not a worst case and a higher rate is not a target."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    // MARK: - Verified inputs and assumptions

    private var verifiedInputs: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Label {
                    Text("Verified inputs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(ManotiColor.forHex("#27AE60"))
                }

                Spacer()

                Text("Not projected")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if verifiedBonds.isEmpty {
                Text("No existing bonds are included. Start fresh uses zero existing bonds and zero starting cash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Remaining net coupons") {
                    AmountText(verifiedCouponTotal, style: .subheadline.weight(.semibold))
                }

                Text(
                    includeExisting
                        ? "From \(verifiedBonds.count) \(verifiedBonds.count == 1 ? "bond" : "bonds") using their exact recorded coupon rates, maturities and withholding tax. Holdings active by the plan start join the ladder. These inputs are verified; everything else on this screen is projected."
                        : "These verified coupons exist but are not included while the toggle is off. Start fresh uses zero existing bonds and zero starting cash. Everything else on this screen is projected."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var assumptions: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            Text("Assumptions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(assumptionsForCurrentResult, id: \.self) { assumption in
                Text("• \(assumption)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                "Not modelled: inflation, fees, defaults, tax changes, liquidity, rate changes, reinvestment risk or your own discipline. Projected values are nominal shillings."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.2), in: .rect(cornerRadius: 16))
    }

    // MARK: - Calculation

    private func calculate(_ settings: ScenarioSettings) async {
        isCalculating = true
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else {
            return
        }

        let existing: [Investment]
        do {
            existing = try investmentService.fetchInvestments(includeMatured: false)
        } catch {
            existing = []
            errorMessage = error.localizedDescription
        }
        let base = InvestmentScenario(
            amountMinor: settings.amountMinor,
            cadenceMonths: settings.cadenceMonths,
            grossRateBasisPoints: settings.rateBasisPoints,
            withholdingTaxBasisPoints: settings.withholdingTaxBasisPoints,
            includeExisting: true,
            useCouponsFirst: settings.useCouponsFirst,
            investExcessCoupons: false,
            startDate: startDate,
            checkpoints: InvestmentScenario.defaultCheckpoints
        )

        var fresh = base
        fresh.includeExisting = false

        var includeExcess = base
        includeExcess.investExcessCoupons = true

        var freshExcess = fresh
        freshExcess.investExcessCoupons = true

        let includeCapped = InvestmentScenarioEngine.runSensitivity(
            base,
            existingInvestments: existing
        )
        let freshCapped = InvestmentScenarioEngine.runSensitivity(
            fresh,
            existingInvestments: existing
        )
        let includeExcessResults = InvestmentScenarioEngine.runSensitivity(
            includeExcess,
            existingInvestments: existing
        )
        let freshExcessResults = InvestmentScenarioEngine.runSensitivity(
            freshExcess,
            existingInvestments: existing
        )

        guard !Task.isCancelled else {
            return
        }

        existingInvestments = existing
        self.includeCapped = includeCapped
        self.freshCapped = freshCapped
        self.includeExcess = includeExcessResults
        self.freshExcess = freshExcessResults
        isCalculating = false
    }

    // MARK: - Derived values

    private var withholdingTaxBasisPoints: Int {
        appService.withholdingTaxBasisPoints
    }

    private var rateBasisPoints: Int {
        Int(grossRatePercent * 100)
    }

    private var netRateBasisPoints: Int {
        rateBasisPoints * (10_000 - withholdingTaxBasisPoints) / 10_000
    }

    private var settings: ScenarioSettings {
        ScenarioSettings(
            amountMinor: Int64(amountMinor),
            cadenceMonths: cadenceMonths,
            rateBasisPoints: rateBasisPoints,
            withholdingTaxBasisPoints: withholdingTaxBasisPoints,
            useCouponsFirst: useCouponsFirst,
            refreshToken: refreshToken
        )
    }

    private var includeResults: [InvestmentScenarioResult] {
        policy == .capped ? includeCapped : includeExcess
    }

    private var freshResults: [InvestmentScenarioResult] {
        policy == .capped ? freshCapped : freshExcess
    }

    private var currentInclude: InvestmentScenarioResult? {
        result(includeResults)
    }

    private var currentFresh: InvestmentScenarioResult? {
        result(freshResults)
    }

    private var sensitivityResults: [InvestmentScenarioResult] {
        sensitivityScenario ? includeResults : freshResults
    }

    private var verifiedBonds: [Investment] {
        existingInvestments.filter { $0.type == .treasuryBond && !$0.isSoftDeleted && $0.status != .matured }
    }

    private var verifiedCouponTotal: Money {
        let currency = CurrencyCatalog.defaultCurrency
        let total = verifiedBonds.reduce(into: Int64(0)) { partial, investment in
            partial += InvestmentMath.totalNetCoupons(for: investment, from: Date.now)
        }
        return Money(minorUnits: total, currency: currency)
    }

    private var chartPoints: [ScenarioChartPoint] {
        guard let reference = currentChartResult else {
            return []
        }

        let results =
            policy == .capped
            ? (includeExisting ? includeCapped : freshCapped)
            : (includeExisting ? includeExcess : freshExcess)
        let calendar = InvestmentMath.calendar

        return reference.series.map { point in
            let year = calendar.component(.year, from: point.date)
            let values = results.compactMap { result in
                result.series.first {
                    calendar.component(.year, from: $0.date) == year
                }?.totalValue.minorUnits
            }
            return ScenarioChartPoint(
                year: year,
                contributions: double(point.contributions),
                value: double(point.totalValue),
                low: double(values.min() ?? point.totalValue.minorUnits),
                high: double(values.max() ?? point.totalValue.minorUnits)
            )
        }
    }

    private var currentChartResult: InvestmentScenarioResult? {
        includeExisting ? currentInclude : currentFresh
    }

    private var selectedPoint: ScenarioChartPoint? {
        chartPoints.first { $0.year == selectedYear }
            ?? chartPoints.min { abs($0.year - selectedYear) < abs($1.year - selectedYear) }
    }

    private var firstChartYear: Int {
        chartPoints.first?.year ?? selectedYear
    }

    private var lastChartYear: Int {
        chartPoints.last?.year ?? selectedYear
    }

    private var assumptionsForCurrentResult: [String] {
        currentInclude?.assumptions ?? currentFresh?.assumptions ?? []
    }

    private var rateLabel: String {
        "\(percent(rateBasisPoints))%"
    }

    private func result(_ results: [InvestmentScenarioResult]) -> InvestmentScenarioResult? {
        results.first { $0.grossRateBasisPoints == rateBasisPoints }
            ?? results.first { $0.grossRateBasisPoints == InvestmentScenario.defaultGrossRateBasisPoints }
            ?? results.last
    }

    private func band(_ results: [InvestmentScenarioResult], year: Int) -> MoneyBand? {
        let values = results.compactMap { $0.checkpoint(for: year)?.totalValue.minorUnits }
        guard let low = values.min(), let high = values.max() else {
            return nil
        }

        return MoneyBand(lowMinor: low, highMinor: high)
    }

    private func atRateValue(_ results: [InvestmentScenarioResult], year: Int) -> Int64? {
        result(results)?.checkpoint(for: year)?.totalValue.minorUnits
    }

    private func valueLabel(_ results: [InvestmentScenarioResult], rate: Int, year: Int) -> String {
        guard let result = results.first(where: { $0.grossRateBasisPoints == rate }),
            let checkpoint = result.checkpoint(for: year)
        else {
            return "—"
        }

        return AmountMask.text(compact(checkpoint.totalValue), hidden: amountsHidden)
    }

    private func selfFundingLabel(_ result: InvestmentScenarioResult?) -> String {
        guard let result else {
            return "—"
        }

        guard let year = result.selfFundingYear else {
            return "Not yet"
        }

        return String(year)
    }

    private func compact(_ money: Money) -> String {
        compact(double(money))
    }

    private func compact(_ amount: Double) -> String {
        let absolute = abs(amount)
        let divisor: Double
        let suffix: String

        switch absolute {
            case 1_000_000...:
                divisor = 1_000_000
                suffix = "M"
            case 1_000...:
                divisor = 1_000
                suffix = "k"
            default:
                divisor = 1
                suffix = ""
        }

        let value = amount / divisor
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = divisor == 1 ? 0 : 2
        formatter.maximumFractionDigits = divisor == 1 ? 0 : 2

        let text = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(text)\(suffix)"
    }

    private func double(_ money: Money) -> Double {
        NSDecimalNumber(decimal: money.decimalValue).doubleValue
    }

    private func double(_ minorUnits: Int64) -> Double {
        NSDecimalNumber(decimal: Decimal(minorUnits) / 100).doubleValue
    }

    private func percent(_ basisPoints: Int) -> String {
        "\(Decimal(basisPoints) / 100)"
    }
}

// MARK: - Supporting types

private enum ScenarioPolicy: String, CaseIterable, Identifiable {
    case capped
    case excess

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
            case .capped: "Capped"
            case .excess: "Reinvest all"
        }
    }

    var label: String {
        switch self {
            case .capped: "Capped at your contribution"
            case .excess: "Reinvest all coupons"
        }
    }

    var explanation: String {
        switch self {
            case .capped:
                "Each purchase stays at your contribution. Once the coupon pool is larger, the surplus remains unused cash and the bond ladder plateaus."
            case .excess:
                "When coupons exceed your contribution, the whole pool buys more bonds. This removes the plateau and is the higher, less conservative case."
        }
    }
}

private struct ScenarioSettings: Hashable {
    let amountMinor: Int64
    let cadenceMonths: Int
    let rateBasisPoints: Int
    let withholdingTaxBasisPoints: Int
    let useCouponsFirst: Bool
    let refreshToken: Int
}

private struct MoneyBand {
    let lowMinor: Int64
    let highMinor: Int64
}

private struct ScenarioChartPoint: Identifiable {
    let year: Int
    let contributions: Double
    let value: Double
    let low: Double
    let high: Double

    var id: Int { year }
}

private struct CheckpointBandRow: View {
    let title: String
    let band: MoneyBand
    let atRate: Int64?
    let rateLabel: String

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(AmountMask.text(rangeText, hidden: amountsHidden))
                .font(.caption.weight(.medium))
                .monospacedDigit()

            if let atRate {
                Text(AmountMask.text(compact(atRate), hidden: amountsHidden))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(AmountMask.text(rangeText, hidden: amountsHidden)), at \(rateLabel) \(atRate.map { AmountMask.text(compact($0), hidden: amountsHidden) } ?? "—")"
        )
    }

    private var rangeText: String {
        let low = compact(band.lowMinor)
        let high = compact(band.highMinor)
        return low == high ? low : "\(low)–\(high)"
    }

    private func compact(_ minorUnits: Int64) -> String {
        let amount = NSDecimalNumber(decimal: Decimal(minorUnits) / 100).doubleValue
        let absolute = abs(amount)
        let divisor: Double = absolute >= 1_000_000 ? 1_000_000 : (absolute >= 1_000 ? 1_000 : 1)
        let suffix = divisor == 1_000_000 ? "M" : (divisor == 1_000 ? "k" : "")

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = divisor == 1 ? 0 : 2
        formatter.maximumFractionDigits = divisor == 1 ? 0 : 2

        let value = amount / divisor
        let text = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(text)\(suffix)"
    }
}
