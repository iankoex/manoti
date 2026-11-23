//
//  InvestmentScenario.swift
//  AppModels
//

import Foundation

/// Inputs for the illustrative “what if I keep buying bonds?” projection.
///
/// A scenario never writes records. It models a ladder of 20-year par bonds funded by new
/// cash and, optionally, by coupons from the ladder and from existing holdings.
nonisolated public struct InvestmentScenario: Equatable, Sendable {
    /// Contribution per cadence in minor units (KES 50,000 is 5,000,000).
    public var amountMinor: Int64
    /// 1, 2, 3 or 6 months.
    public var cadenceMonths: Int
    /// Gross annual coupon and reinvestment rate in basis points.
    public var grossRateBasisPoints: Int
    /// Withholding tax in basis points.
    public var withholdingTaxBasisPoints: Int
    /// Include the actual coupons, maturities and face of existing bonds.
    public var includeExisting: Bool
    /// Spend coupon cash on purchases before adding new cash.
    public var useCouponsFirst: Bool
    /// Buy more than the contribution when the coupon pool is larger.
    public var investExcessCoupons: Bool
    public var startDate: Date
    public var checkpoints: [Int]
    public var currency: Currency

    public static let defaultAmountMinor: Int64 = 5_000_000
    public static let amountLowerBoundMinor: Int64 = 1_000_000
    public static let amountUpperBoundMinor: Int64 = 20_000_000
    public static let amountStepMinor: Int64 = 500_000
    public static let cadenceOptions = [1, 2, 3, 6]
    public static let grossRateRange = 800...1500
    public static let defaultGrossRateBasisPoints = 1200
    public static let defaultWithholdingTaxBasisPoints = 1000
    /// Reference points for the sensitivity band.
    ///
    /// The slider rate is always added too.
    public static let sensitivityGrossRatesBasisPoints = [800, 1000, 1200]
    public static let defaultCheckpoints = [2040, 2050, 2060]

    /// The disclaimer shown with every what-if projection.
    public static let disclaimer =
        "Illustrative projection, not financial advice. Assumes a constant reinvestment rate, no fees or default, 10% withholding tax, and nominal shillings. Actual results depend on available rates, tax changes, inflation, liquidity and your discipline. Consult a licensed financial adviser before acting."

    public init(
        amountMinor: Int64 = InvestmentScenario.defaultAmountMinor,
        cadenceMonths: Int = 2,
        grossRateBasisPoints: Int = InvestmentScenario.defaultGrossRateBasisPoints,
        withholdingTaxBasisPoints: Int = InvestmentScenario.defaultWithholdingTaxBasisPoints,
        includeExisting: Bool = true,
        useCouponsFirst: Bool = true,
        investExcessCoupons: Bool = false,
        startDate: Date = InvestmentScenario.defaultStartDate(),
        checkpoints: [Int] = InvestmentScenario.defaultCheckpoints,
        currency: Currency = CurrencyCatalog.defaultCurrency
    ) {
        self.amountMinor = amountMinor
        self.cadenceMonths = cadenceMonths
        self.grossRateBasisPoints = grossRateBasisPoints
        self.withholdingTaxBasisPoints = withholdingTaxBasisPoints
        self.includeExisting = includeExisting
        self.useCouponsFirst = useCouponsFirst
        self.investExcessCoupons = investExcessCoupons
        self.startDate = startDate
        self.checkpoints = checkpoints
        self.currency = currency
    }

    /// The net rate after withholding tax.
    public var netRateBasisPoints: Int {
        let tax = min(max(withholdingTaxBasisPoints, 0), 10_000)
        return grossRateBasisPoints * (10_000 - tax) / 10_000
    }

    /// January 1 of the next calendar year, a clean start for an annual plan.
    public static func defaultStartDate(
        from date: Date = Date(),
        calendar: Calendar = InvestmentMath.calendar
    ) -> Date {
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? date
    }
}

/// A year-end point in a scenario, for charts and checkpoint chips.
nonisolated public struct InvestmentScenarioPoint: Identifiable, Equatable, Sendable {
    public let date: Date
    public let contributions: Money
    public let totalValue: Money

    public var id: Date { date }

    public init(date: Date, contributions: Money, totalValue: Money) {
        self.date = date
        self.contributions = contributions
        self.totalValue = totalValue
    }
}

/// The measured position at one checkpoint year.
nonisolated public struct InvestmentScenarioCheckpoint: Identifiable, Equatable, Sendable {
    public let year: Int
    public let totalValue: Money
    public let activeFace: Money
    public let couponCash: Money
    public let contributions: Money
    public let couponFundedPurchases: Money

    public var id: Int { year }

    public init(
        year: Int,
        totalValue: Money,
        activeFace: Money,
        couponCash: Money,
        contributions: Money,
        couponFundedPurchases: Money
    ) {
        self.year = year
        self.totalValue = totalValue
        self.activeFace = activeFace
        self.couponCash = couponCash
        self.contributions = contributions
        self.couponFundedPurchases = couponFundedPurchases
    }
}

/// A single illustrative run of the bond ladder.
nonisolated public struct InvestmentScenarioResult: Equatable, Sendable {
    public let scenario: InvestmentScenario
    public let includeExisting: Bool
    public let grossRateBasisPoints: Int
    public let netRateBasisPoints: Int
    /// Cash added from outside the ladder.
    public let totalNewCash: Money
    /// Purchases paid for from coupon cash.
    public let couponFundedPurchases: Money
    /// Face value of every bond bought during the run.
    public let totalPurchases: Money
    public let totalCouponsReceived: Money
    /// Year of the last external top-up; nil when coupons never cover a purchase.
    public let selfFundingYear: Int?
    /// Cash left at the final checkpoint.
    public let unusedCouponCash: Money
    public let checkpoints: [InvestmentScenarioCheckpoint]
    public let series: [InvestmentScenarioPoint]
    public let assumptions: [String]

    public init(
        scenario: InvestmentScenario,
        includeExisting: Bool,
        grossRateBasisPoints: Int,
        netRateBasisPoints: Int,
        totalNewCash: Money,
        couponFundedPurchases: Money,
        totalPurchases: Money,
        totalCouponsReceived: Money,
        selfFundingYear: Int?,
        unusedCouponCash: Money,
        checkpoints: [InvestmentScenarioCheckpoint],
        series: [InvestmentScenarioPoint],
        assumptions: [String]
    ) {
        self.scenario = scenario
        self.includeExisting = includeExisting
        self.grossRateBasisPoints = grossRateBasisPoints
        self.netRateBasisPoints = netRateBasisPoints
        self.totalNewCash = totalNewCash
        self.couponFundedPurchases = couponFundedPurchases
        self.totalPurchases = totalPurchases
        self.totalCouponsReceived = totalCouponsReceived
        self.selfFundingYear = selfFundingYear
        self.unusedCouponCash = unusedCouponCash
        self.checkpoints = checkpoints
        self.series = series
        self.assumptions = assumptions
    }

    public func checkpoint(for year: Int) -> InvestmentScenarioCheckpoint? {
        checkpoints.first { $0.year == year }
    }
}
