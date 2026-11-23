//
//  InvestmentScenarioEngine.swift
//  AppModels
//

import Foundation

/// Pure bond-ladder projection for the Investments what-if screen.
///
/// Every purchase is a 20-year par bond at the scenario's gross rate. Coupons and matured
/// principal land in a cash pool; each cadence purchase uses the pool first and new cash for
/// the shortfall. When “invest excess coupons” is off, purchases stay capped at the
/// contribution and the surplus stays as unused cash. When it is on, the purchase grows to
/// the whole pool so all coupon cash is reinvested.
///
/// The ladder is book value: active face plus cash. It is not a market-price forecast.
nonisolated public enum InvestmentScenarioEngine {
    public static let newBondTermYears = 20

    /// Runs the scenario once.
    ///
    /// Existing investments are read-only and never modified.
    public static func run(
        _ scenario: InvestmentScenario,
        existingInvestments: [Investment] = [],
        calendar: Calendar = InvestmentMath.calendar
    ) -> InvestmentScenarioResult {
        let currency = scenario.currency
        let startDay = calendar.startOfDay(for: scenario.startDate)
        let startYear = calendar.component(.year, from: startDay)
        let checkpointYears =
            Array(Set(scenario.checkpoints))
            .filter { $0 >= startYear }
            .sorted()
        let lastYear = max(checkpointYears.last ?? startYear, startYear)
        let endDay =
            calendar.date(from: DateComponents(year: lastYear, month: 12, day: 31))
            ?? startDay

        var couponEvents: [Date: Int64] = [:]
        var maturityEvents: [Date: Int64] = [:]
        var activeFaceMinor: Int64 = 0
        var cashMinor: Int64 = 0
        var totalNewCashMinor: Int64 = 0
        var couponFundedMinor: Int64 = 0
        var totalPurchasesMinor: Int64 = 0
        var totalCouponsMinor: Int64 = 0
        var lastTopUpDay: Date?

        if scenario.includeExisting {
            for investment in existingInvestments
            where !investment.isSoftDeleted && investment.currencyCode == currency.code
                && isIncluded(investment, on: startDay, calendar: calendar)
            {
                switch investment.type {
                    case .treasuryBond:
                        includeBond(
                            investment,
                            from: startDay,
                            currency: currency,
                            couponEvents: &couponEvents,
                            maturityEvents: &maturityEvents,
                            activeFaceMinor: &activeFaceMinor,
                            calendar: calendar
                        )
                    case .treasuryBill:
                        includeBill(
                            investment,
                            from: startDay,
                            maturityEvents: &maturityEvents,
                            activeFaceMinor: &activeFaceMinor,
                            calendar: calendar
                        )
                    case .moneyMarket:
                        cashMinor += investment.currentValueMinor(asOf: startDay)
                }
            }
        }

        let grossRate = min(max(scenario.grossRateBasisPoints, 0), 10_000)
        let tax = min(max(scenario.withholdingTaxBasisPoints, 0), 10_000)
        let cadence = max(1, scenario.cadenceMonths)
        let contribution = max(0, scenario.amountMinor)
        let usesCouponsFirst = scenario.useCouponsFirst
        let investExcess = scenario.investExcessCoupons && usesCouponsFirst

        var series: [InvestmentScenarioPoint] = [
            InvestmentScenarioPoint(
                date: startDay,
                contributions: .zero(in: currency),
                totalValue: Money(minorUnits: activeFaceMinor + cashMinor, currency: currency)
            )
        ]
        var checkpoints: [InvestmentScenarioCheckpoint] = []
        var day = startDay
        var nextPurchaseDay = startDay

        while day <= endDay {
            if let coupon = couponEvents[day] {
                cashMinor += coupon
                totalCouponsMinor += coupon
            }

            if let maturing = maturityEvents[day] {
                cashMinor += maturing
                activeFaceMinor = max(0, activeFaceMinor - maturing)
            }

            if day >= nextPurchaseDay && contribution > 0 {
                let pool = cashMinor
                var purchase = contribution

                if investExcess && pool > purchase {
                    purchase = pool
                }

                let fromCoupons = usesCouponsFirst ? min(pool, purchase) : 0
                cashMinor -= fromCoupons
                couponFundedMinor += fromCoupons

                let topUp = purchase - fromCoupons
                if topUp > 0 {
                    totalNewCashMinor += topUp
                    lastTopUpDay = day
                }

                totalPurchasesMinor += purchase
                activeFaceMinor += purchase
                addNewBond(
                    faceMinor: purchase,
                    purchaseDay: day,
                    grossRateBasisPoints: grossRate,
                    withholdingTaxBasisPoints: tax,
                    couponEvents: &couponEvents,
                    maturityEvents: &maturityEvents,
                    calendar: calendar
                )

                nextPurchaseDay = calendar.date(byAdding: .month, value: cadence, to: day) ?? day
            }

            let components = calendar.dateComponents([.month, .day, .year], from: day)
            if components.month == 12, components.day == 31, let year = components.year {
                let value = Money(minorUnits: activeFaceMinor + cashMinor, currency: currency)

                if year >= startYear {
                    series.append(
                        InvestmentScenarioPoint(
                            date: day,
                            contributions: Money(minorUnits: totalNewCashMinor, currency: currency),
                            totalValue: value
                        )
                    )
                }

                if checkpointYears.contains(year) {
                    checkpoints.append(
                        InvestmentScenarioCheckpoint(
                            year: year,
                            totalValue: value,
                            activeFace: Money(minorUnits: activeFaceMinor, currency: currency),
                            couponCash: Money(minorUnits: cashMinor, currency: currency),
                            contributions: Money(minorUnits: totalNewCashMinor, currency: currency),
                            couponFundedPurchases: Money(
                                minorUnits: couponFundedMinor,
                                currency: currency
                            )
                        )
                    )
                }
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        let selfFundingYear = lastTopUpDay.map { calendar.component(.year, from: $0) }

        return InvestmentScenarioResult(
            scenario: scenario,
            includeExisting: scenario.includeExisting,
            grossRateBasisPoints: grossRate,
            netRateBasisPoints: grossRate * (10_000 - tax) / 10_000,
            totalNewCash: Money(minorUnits: totalNewCashMinor, currency: currency),
            couponFundedPurchases: Money(minorUnits: couponFundedMinor, currency: currency),
            totalPurchases: Money(minorUnits: totalPurchasesMinor, currency: currency),
            totalCouponsReceived: Money(minorUnits: totalCouponsMinor, currency: currency),
            selfFundingYear: selfFundingYear,
            unusedCouponCash: Money(minorUnits: cashMinor, currency: currency),
            checkpoints: checkpoints,
            series: series,
            assumptions: assumptions(
                for: scenario,
                grossRateBasisPoints: grossRate,
                withholdingTaxBasisPoints: tax
            )
        )
    }

    /// Runs the same scenario at several gross rates so the UI can show a range.
    ///
    /// The scenario's own rate is always included, even when it sits outside the usual
    /// 8%, 10% and 12% reference points.
    public static func runSensitivity(
        _ scenario: InvestmentScenario,
        existingInvestments: [Investment] = [],
        grossRatesBasisPoints: [Int] = InvestmentScenario.sensitivityGrossRatesBasisPoints,
        calendar: Calendar = InvestmentMath.calendar
    ) -> [InvestmentScenarioResult] {
        var rates = Set(grossRatesBasisPoints)
        rates.insert(scenario.grossRateBasisPoints)

        return rates.sorted().map { rate in
            var copy = scenario
            copy.grossRateBasisPoints = rate
            return run(copy, existingInvestments: existingInvestments, calendar: calendar)
        }
    }

    // MARK: - Existing holdings

    /// A pending holding joins the ladder only once its settlement has passed.
    private static func isIncluded(
        _ investment: Investment,
        on startDay: Date,
        calendar: Calendar
    ) -> Bool {
        switch investment.status {
            case .active:
                return true
            case .matured:
                return false
            case .pending:
                guard let settlement = investment.settlementDate else {
                    return false
                }

                return calendar.startOfDay(for: settlement) <= startDay
        }
    }

    private static func includeBond(
        _ investment: Investment,
        from startDay: Date,
        currency: Currency,
        couponEvents: inout [Date: Int64],
        maturityEvents: inout [Date: Int64],
        activeFaceMinor: inout Int64,
        calendar: Calendar
    ) {
        guard let maturity = investment.maturityDate else {
            activeFaceMinor += investment.nominalMinor
            return
        }

        let maturityDay = calendar.startOfDay(for: maturity)
        guard maturityDay >= startDay else {
            return
        }

        let settlement = investment.settlementDate.map { calendar.startOfDay(for: $0) }
        let couponStart = max(startDay, settlement ?? startDay)
        let schedule = InvestmentMath.couponSchedule(
            for: investment,
            from: couponStart,
            calendar: calendar
        )

        for entry in schedule {
            let day = calendar.startOfDay(for: entry.date)
            guard day <= maturityDay else {
                continue
            }
            couponEvents[day, default: 0] += entry.netMinor
        }

        maturityEvents[maturityDay, default: 0] += investment.nominalMinor
        activeFaceMinor += investment.nominalMinor
    }

    private static func includeBill(
        _ investment: Investment,
        from startDay: Date,
        maturityEvents: inout [Date: Int64],
        activeFaceMinor: inout Int64,
        calendar: Calendar
    ) {
        guard let maturity = investment.maturityDate else {
            return
        }

        let maturityDay = calendar.startOfDay(for: maturity)
        guard maturityDay >= startDay else {
            return
        }

        maturityEvents[maturityDay, default: 0] += investment.nominalMinor
        activeFaceMinor += investment.nominalMinor
    }

    // MARK: - New bonds

    private static func addNewBond(
        faceMinor: Int64,
        purchaseDay: Date,
        grossRateBasisPoints: Int,
        withholdingTaxBasisPoints: Int,
        couponEvents: inout [Date: Int64],
        maturityEvents: inout [Date: Int64],
        calendar: Calendar
    ) {
        guard faceMinor > 0 else {
            return
        }

        let maturity =
            calendar.date(byAdding: .year, value: newBondTermYears, to: purchaseDay) ?? purchaseDay
        maturityEvents[maturity, default: 0] += faceMinor

        let gross = InvestmentMath.grossCouponMinor(
            nominalMinor: faceMinor,
            couponRateBasisPoints: Decimal(grossRateBasisPoints)
        )
        let tax = InvestmentMath.taxMinor(
            grossMinor: gross,
            withholdingTaxBasisPoints: withholdingTaxBasisPoints
        )
        let net = gross - tax

        guard net > 0 else {
            return
        }

        var couponDay = purchaseDay
        while let next = calendar.date(
            byAdding: .day,
            value: InvestmentMath.defaultCouponPeriodDays,
            to: couponDay
        ), next < maturity {
            couponEvents[next, default: 0] += net
            couponDay = next
        }
    }

    // MARK: - Assumptions

    private static func assumptions(
        for scenario: InvestmentScenario,
        grossRateBasisPoints: Int,
        withholdingTaxBasisPoints: Int
    ) -> [String] {
        let grossPercent = Decimal(grossRateBasisPoints) / 100
        let taxPercent = Decimal(withholdingTaxBasisPoints) / 100
        let netPercent = Decimal(grossRateBasisPoints * (10_000 - withholdingTaxBasisPoints) / 10_000) / 100

        var assumptions = [
            "Illustrative projection only. Not a promise and not financial advice.",
            "Each purchase is a \(newBondTermYears)-year par bond at \(grossPercent)% gross, net of \(taxPercent)% withholding tax (\(netPercent)% net).",
            "Bond values are book value (face), not market prices.",
            "No fees, defaults, rate changes, inflation or liquidity constraints are modelled.",
        ]

        if scenario.includeExisting {
            assumptions.append(
                "Your existing bonds are included with their actual coupon schedules, maturities and withholding tax. Money market accounts join the cash pool at their current after-tax value."
            )
        } else {
            assumptions.append(
                "Start fresh: zero existing bonds and zero starting cash. Contributions still apply."
            )
        }

        if !scenario.useCouponsFirst {
            assumptions.append("Every purchase is new cash; coupons accumulate as unused cash.")
        } else if scenario.investExcessCoupons {
            assumptions.append(
                "Coupon cash funds each purchase first; any excess is invested in full at the same rate."
            )
        } else {
            assumptions.append(
                "Purchases are capped at the contribution amount. Excess coupon cash is left uninvested."
            )
        }

        return assumptions
    }
}
