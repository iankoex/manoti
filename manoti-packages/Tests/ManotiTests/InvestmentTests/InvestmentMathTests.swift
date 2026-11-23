//
//  InvestmentMathTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("InvestmentMath")
struct InvestmentMathTests {
    /// The 21 Nov 2026 reference date used by the real CBK portfolio export.
    private static let asOf =
        InvestmentMath.calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)) ?? Date()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        InvestmentMath.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func bond(
        issueNumber: String,
        nominalMinor: Int64,
        couponRateBasisPoints: Decimal,
        firstCouponDate: Date,
        maturityDate: Date,
        withholdingTaxBasisPoints: Int = 1000,
        taxExempt: Bool = false,
        overrides: [Date] = []
    ) -> Investment {
        Investment(
            type: .treasuryBond,
            issueNumber: issueNumber,
            nominalMinor: nominalMinor,
            couponRateBasisPoints: couponRateBasisPoints,
            withholdingTaxBasisPoints: withholdingTaxBasisPoints,
            taxExempt: taxExempt,
            purchaseDate: date(2026, 1, 1),
            firstCouponDate: firstCouponDate,
            maturityDate: maturityDate,
            cashInvestedMinor: nominalMinor,
            status: .active,
            couponDateOverrides: overrides
        )
    }

    // MARK: - Real CBK terms

    @Test("FXD1/2021/025 reconciles the 2 Nov 2026 coupon and 39 remaining coupons")
    func fxd2021Coupon() {
        let investment = bond(
            issueNumber: "FXD1/2021/025",
            nominalMinor: 15_000_000,
            couponRateBasisPoints: Decimal(string: "1392.4") ?? 0,
            firstCouponDate: date(2026, 11, 2),
            maturityDate: date(2046, 4, 9)
        )

        #expect(InvestmentMath.grossCouponMinor(for: investment) == 1_044_300)
        #expect(InvestmentMath.taxMinor(for: investment) == 104_430)
        #expect(InvestmentMath.netCouponMinor(for: investment) == 939_870)

        let schedule = InvestmentMath.couponSchedule(for: investment, from: Self.asOf)
        #expect(schedule.count == 39)
        #expect(schedule.first.map { InvestmentMath.calendar.isDate($0.date, inSameDayAs: date(2027, 5, 3)) } == true)
        #expect(schedule.last.map { InvestmentMath.calendar.isDate($0.date, inSameDayAs: date(2046, 4, 9)) } == true)
        #expect(InvestmentMath.totalNetCoupons(for: investment, from: Self.asOf) == 36_654_930)
    }

    @Test("FXD1/2022/025 reconciles the 19 Oct 2026 coupon and 42 remaining coupons")
    func fxd2022Coupon() {
        let investment = bond(
            issueNumber: "FXD1/2022/025",
            nominalMinor: 10_000_000,
            couponRateBasisPoints: Decimal(string: "1418.8") ?? 0,
            firstCouponDate: date(2026, 10, 19),
            maturityDate: date(2047, 9, 23)
        )

        #expect(InvestmentMath.grossCouponMinor(for: investment) == 709_400)
        #expect(InvestmentMath.taxMinor(for: investment) == 70_940)
        #expect(InvestmentMath.netCouponMinor(for: investment) == 638_460)

        let schedule = InvestmentMath.couponSchedule(for: investment, from: Self.asOf)
        #expect(schedule.count == 42)
        #expect(schedule.first.map { InvestmentMath.calendar.isDate($0.date, inSameDayAs: date(2027, 4, 19)) } == true)
        #expect(schedule.last.map { InvestmentMath.calendar.isDate($0.date, inSameDayAs: date(2047, 9, 23)) } == true)
        #expect(InvestmentMath.totalNetCoupons(for: investment, from: Self.asOf) == 26_815_320)
    }

    @Test("FXD1/2019/015 uses the prospectus dates and reconciles 15 coupons")
    func fxd2019Coupon() {
        let prospectusDates = [
            date(2027, 1, 18),
            date(2027, 7, 19),
            date(2028, 1, 17),
            date(2028, 7, 17),
            date(2029, 1, 15),
            date(2029, 7, 16),
            date(2030, 1, 14),
            date(2030, 7, 15),
            date(2031, 1, 13),
            date(2031, 7, 14),
            date(2032, 1, 12),
            date(2032, 7, 12),
            date(2033, 1, 10),
            date(2033, 7, 11),
            date(2034, 1, 9),
        ]

        let generated = bond(
            issueNumber: "FXD1/2019/015",
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            firstCouponDate: date(2027, 1, 18),
            maturityDate: date(2034, 1, 9)
        )
        let stored = bond(
            issueNumber: "FXD1/2019/015",
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            firstCouponDate: date(2027, 1, 18),
            maturityDate: date(2034, 1, 9),
            overrides: prospectusDates
        )

        #expect(InvestmentMath.grossCouponMinor(for: generated) == 321_425)
        #expect(InvestmentMath.taxMinor(for: generated) == 32_142)
        #expect(InvestmentMath.netCouponMinor(for: generated) == 289_283)
        #expect(InvestmentMath.totalNetCoupons(for: generated, from: Self.asOf) == 4_339_245)

        let generatedDates = InvestmentMath.couponSchedule(for: generated, from: Self.asOf).map(\.date)
        let storedDates = InvestmentMath.couponSchedule(for: stored, from: Self.asOf).map(\.date)

        #expect(generatedDates == prospectusDates)
        #expect(storedDates == prospectusDates)
        #expect(storedDates.count == 15)
    }

    @Test("A tax-exempt bond withholds nothing")
    func taxExemptCoupon() {
        let investment = bond(
            issueNumber: "EXEMPT",
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            firstCouponDate: date(2027, 1, 18),
            maturityDate: date(2034, 1, 9),
            taxExempt: true
        )

        #expect(InvestmentMath.taxMinor(for: investment) == 0)
        #expect(InvestmentMath.netCouponMinor(for: investment) == 321_425)
    }

    // MARK: - Accrued interest and dirty price

    @Test("Accrued interest uses actual/365 and the dirty price adds it to the clean price")
    func accruedInterestAndDirtyPrice() {
        let clean = InvestmentMath.cleanPriceMinor(
            nominalMinor: 5_000_000, pricePer100: Decimal(string: "101.0567") ?? 0)
        let accrued = InvestmentMath.accruedInterestMinor(
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            daysSinceLastCoupon: 90
        )
        let estimate = InvestmentMath.accruedInterestMinor(
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            daysSinceLastCoupon: 126
        )

        #expect(clean == 5_052_835)
        #expect(accrued == 158_511)
        #expect(estimate == 221_915)
        #expect(InvestmentMath.dirtyPriceMinor(cleanPriceMinor: clean, accruedInterestMinor: accrued) == 5_211_346)

        // The broker statement's actual dirty cash: clean 5,052,835 + accrued 222,525.
        #expect(InvestmentMath.dirtyPriceMinor(cleanPriceMinor: 5_052_835, accruedInterestMinor: 222_525) == 5_275_360)
        #expect(InvestmentMath.scaledCleanPrice(pricePer100: Decimal(string: "101.0567") ?? 0) == 1_010_567)
    }

    @Test("Zero or negative accrued days produce no accrued interest")
    func accruedInterestGuards() {
        #expect(
            InvestmentMath.accruedInterestMinor(
                nominalMinor: 5_000_000,
                couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
                daysSinceLastCoupon: 0
            ) == 0
        )
        #expect(
            InvestmentMath.accruedInterestMinor(
                nominalMinor: 5_000_000,
                couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
                daysSinceLastCoupon: -5
            ) == 0
        )
    }

    // MARK: - Schedule generation

    @Test("A weekend coupon is paid on the next business day")
    func businessDayAdjustment() {
        let saturday = date(2027, 1, 2)
        let investment = bond(
            issueNumber: "WEEKEND",
            nominalMinor: 1_000_000,
            couponRateBasisPoints: Decimal(1000),
            firstCouponDate: saturday,
            maturityDate: date(2027, 12, 31)
        )

        #expect(InvestmentMath.adjustToBusinessDay(saturday) == date(2027, 1, 4))

        let schedule = InvestmentMath.couponSchedule(for: investment, from: saturday)
        #expect(schedule.first.map { InvestmentMath.calendar.isDate($0.date, inSameDayAs: date(2027, 1, 4)) } == true)
    }

    @Test("Before the first coupon the full schedule remains")
    func scheduleBeforeFirstCoupon() {
        let investment = bond(
            issueNumber: "FXD1/2019/015",
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            firstCouponDate: date(2027, 1, 18),
            maturityDate: date(2034, 1, 9)
        )

        #expect(InvestmentMath.couponSchedule(for: investment, from: date(2026, 1, 1)).count == 15)
        #expect(InvestmentMath.totalNetCoupons(for: investment, from: date(2026, 1, 1)) == 4_339_245)
    }

    // MARK: - Money market

    @Test("Money market value compounds daily at the after-tax rate")
    func moneyMarketValue() {
        let value = InvestmentMath.moneyMarketValueMinor(
            principalMinor: 10_000_000,
            annualRateBasisPoints: Decimal(1000),
            withholdingTaxBasisPoints: 1000,
            days: 365
        )

        // 100,000 × (1 + 9%/365)^365 = 109,416.21.
        #expect(value == 10_941_621)
        #expect(
            InvestmentMath.moneyMarketValueMinor(
                principalMinor: 10_000_000,
                annualRateBasisPoints: Decimal(1000),
                withholdingTaxBasisPoints: 1000,
                days: 0
            ) == 10_000_000
        )
    }

    // MARK: - Projection

    @Test("Projection uses the configured reinvestment rate, not the coupon rate")
    func projectionFixture() {
        let asOf = date(2027, 1, 1)
        let investment = Investment(
            type: .treasuryBond,
            issueNumber: "FIXTURE",
            nominalMinor: 10_000_000,
            couponRateBasisPoints: Decimal(1000),
            withholdingTaxBasisPoints: 1000,
            purchaseDate: asOf,
            firstCouponDate: asOf,
            maturityDate: date(2027, 7, 2),
            cashInvestedMinor: 10_000_000,
            status: .active
        )

        let projection = InvestmentMath.projection(
            for: investment,
            reinvestmentRateBasisPoints: 1200,
            horizonYears: 1,
            asOf: asOf
        )

        #expect(projection.grossReinvestmentRateBasisPoints == 1200)
        #expect(projection.netReinvestmentRateBasisPoints == 1080)
        #expect(projection.taxRateBasisPoints == 1000)
        #expect(projection.totalNetCoupons.minorUnits == 900_000)
        #expect(projection.holdToMaturity.minorUnits == 10_900_000)
        // First coupon compounds one period at 5.4%, the second is paid at maturity.
        #expect(projection.reinvestedAtMaturity.minorUnits == 10_924_300)
        // One-year horizon: 450,000 at 1.054^2 plus 450,000 at 1.054 plus principal.
        #expect(projection.horizonValue.minorUnits == 10_974_212)
        #expect(projection.assumptions.count == 3)
    }

    @Test("Projection at the real FXD1/2021/025 terms totals the real net coupons")
    func projectionRealBond() {
        let investment = bond(
            issueNumber: "FXD1/2021/025",
            nominalMinor: 15_000_000,
            couponRateBasisPoints: Decimal(string: "1392.4") ?? 0,
            firstCouponDate: date(2026, 11, 2),
            maturityDate: date(2046, 4, 9)
        )

        let projection = InvestmentMath.projection(
            for: investment,
            reinvestmentRateBasisPoints: 1200,
            horizonYears: 20,
            asOf: Self.asOf
        )

        #expect(projection.totalNetCoupons.minorUnits == 36_654_930)
        #expect(projection.holdToMaturity.minorUnits == 51_654_930)
        #expect(projection.reinvestedAtMaturity.minorUnits > projection.holdToMaturity.minorUnits)
        #expect(projection.netReinvestmentRateBasisPoints == 1080)
    }
}
