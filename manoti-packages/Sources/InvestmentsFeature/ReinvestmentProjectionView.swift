//
//  ReinvestmentProjectionView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Illustrative per-bond projection at an editable reinvestment rate.
public struct ReinvestmentProjectionView: View {
    @Environment(AppService.self) private var appService

    let investment: Investment

    @State private var rateText = ""
    @State private var selectedYear = 2040

    public init(investment: Investment) {
        self.investment = investment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            header
            rateField
            checkpointChips

            if let projection {
                metrics(projection)
                assumptions(projection)
            } else {
                Text("Enter a reinvestment rate to see the projection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
        .task {
            if rateText.isEmpty {
                let rate = investment.reinvestmentRateBasisPoints ?? appService.reinvestmentRateBasisPoints
                rateText = "\(Decimal(rate) / 100)"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Projection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Illustrative")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, ManotiSpacing.small)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: .capsule)
            }

            Text("Could grow to, if net coupons are reinvested at a constant rate.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rateField: some View {
        LabeledContent("Reinvestment rate") {
            HStack(spacing: ManotiSpacing.small) {
                TextField("12", text: $rateText)
                    .decimalKeyboard()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()

                Text("% gross")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var checkpointChips: some View {
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
                            year == selectedYear ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1),
                            in: .capsule
                        )
                        .foregroundStyle(year == selectedYear ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(year == selectedYear ? .isSelected : [])
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func metrics(_ projection: InvestmentProjection) -> some View {
        let netRate = "\(Decimal(projection.netReinvestmentRateBasisPoints) / 100)%"

        VStack(spacing: ManotiSpacing.small) {
            LabeledContent("Net rate") {
                Text("\(netRate) after tax")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Hold to maturity") {
                AmountText(projection.holdToMaturity, style: .subheadline.weight(.semibold))
            }

            LabeledContent("Reinvested at maturity") {
                AmountText(projection.reinvestedAtMaturity, style: .subheadline.weight(.semibold))
            }

            LabeledContent("At \(selectedYear)") {
                AmountText(projection.horizonValue, style: .headline.weight(.semibold))
            }

            LabeledContent("Total net coupons") {
                AmountText(projection.totalNetCoupons, style: .subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private func assumptions(_ projection: InvestmentProjection) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.tiny) {
            ForEach(projection.assumptions, id: \.self) { assumption in
                Text("• \(assumption)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Nominal shillings, no inflation, no fees and no default. Not a promise or financial advice.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, ManotiSpacing.tiny)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var projection: InvestmentProjection? {
        guard let rate = reinvestmentRateBasisPoints else {
            return nil
        }

        let currentYear = InvestmentMath.calendar.component(.year, from: Date.now)
        let horizon = max(0, selectedYear - currentYear)
        return InvestmentMath.projection(
            for: investment,
            reinvestmentRateBasisPoints: rate,
            horizonYears: horizon,
            asOf: Date.now
        )
    }

    private var reinvestmentRateBasisPoints: Int? {
        let trimmed = rateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return nil
        }

        guard value >= 0, value <= 50 else {
            return nil
        }

        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: handler).intValue
    }
}
