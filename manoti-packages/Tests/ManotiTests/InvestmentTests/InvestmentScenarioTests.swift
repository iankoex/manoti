//
//  InvestmentScenarioTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("Investment scenarios")
struct InvestmentScenarioTests {
    private static let asOf =
        InvestmentMath.calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)) ?? Date()
    private static let planStart =
        InvestmentMath.calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)) ?? Date()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        InvestmentMath.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func realBonds() -> [Investment] {
        let fxd2019Dates = [
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

        return [
            Investment(
                type: .treasuryBond,
                issueNumber: "FXD1/2021/025",
                isin: "KE7000003652",
                issuer: "CBK",
                nominalMinor: 15_000_000,
                couponRateBasisPoints: Decimal(string: "1392.4") ?? 0,
                withholdingTaxBasisPoints: 1000,
                purchaseDate: date(2026, 11, 20),
                firstCouponDate: date(2026, 11, 2),
                maturityDate: date(2046, 4, 9),
                cashInvestedMinor: 15_000_000,
                status: .active
            ),
            Investment(
                type: .treasuryBond,
                issueNumber: "FXD1/2022/025",
                isin: "KE8000005093",
                issuer: "CBK",
                nominalMinor: 10_000_000,
                couponRateBasisPoints: Decimal(string: "1418.8") ?? 0,
                withholdingTaxBasisPoints: 1000,
                purchaseDate: date(2026, 11, 20),
                firstCouponDate: date(2026, 10, 19),
                maturityDate: date(2047, 9, 23),
                cashInvestedMinor: 10_000_000,
                status: .active
            ),
            Investment(
                type: .treasuryBond,
                issueNumber: "FXD1/2019/015",
                isin: "KE5000009430",
                issuer: "CBK",
                nominalMinor: 5_000_000,
                couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
                withholdingTaxBasisPoints: 1000,
                purchaseDate: date(2026, 11, 20),
                firstCouponDate: date(2027, 1, 18),
                maturityDate: date(2034, 1, 9),
                cashInvestedMinor: 5_275_360,
                status: .active,
                couponDateOverrides: fxd2019Dates
            ),
        ]
    }

    private func scenario(
        includeExisting: Bool = true,
        investExcessCoupons: Bool = false,
        rate: Int = 1200
    ) -> InvestmentScenario {
        InvestmentScenario(
            amountMinor: 5_000_000,
            cadenceMonths: 2,
            grossRateBasisPoints: rate,
            withholdingTaxBasisPoints: 1000,
            includeExisting: includeExisting,
            useCouponsFirst: true,
            investExcessCoupons: investExcessCoupons,
            startDate: Self.planStart,
            checkpoints: [2040, 2050, 2060]
        )
    }

    private func run(
        includeExisting: Bool = true,
        investExcessCoupons: Bool = false,
        rate: Int = 1200,
        existing: [Investment]? = nil
    ) -> InvestmentScenarioResult {
        InvestmentScenarioEngine.run(
            scenario(
                includeExisting: includeExisting,
                investExcessCoupons: investExcessCoupons,
                rate: rate
            ),
            existingInvestments: existing ?? realBonds()
        )
    }

    /// Compares a money value in minor units with a major-unit range (KES exponent 2).
    private func isIn(_ money: Money?, _ lowMajor: Int64, _ highMajor: Int64) -> Bool {
        guard let minor = money?.minorUnits else {
            return false
        }

        return ((lowMajor * 100)...(highMajor * 100)).contains(minor)
    }

    // MARK: - Verified inputs

    @Test("The real bonds' remaining net coupons are verified, not projected")
    func verifiedCouponTotals() {
        let bonds = realBonds()
        let totals = bonds.map { InvestmentMath.totalNetCoupons(for: $0, from: Self.asOf) }

        #expect(totals == [36_654_930, 26_815_320, 4_339_245])
        #expect(totals.reduce(Int64(0), +) == 67_809_495)
    }

    // MARK: - Ladder invariants

    @Test("Cash top-ups plus coupon-funded purchases equal total purchases")
    func cashAndCouponPurchasesReconcile() {
        for include in [true, false] {
            for excess in [true, false] {
                let result = run(includeExisting: include, investExcessCoupons: excess)

                #expect(
                    result.totalNewCash.minorUnits + result.couponFundedPurchases.minorUnits
                        == result.totalPurchases.minorUnits
                )
                #expect(result.totalPurchases.minorUnits > 0)
                #expect(result.totalNewCash.minorUnits > 0)
                #expect(result.checkpoints.map(\.year) == [2040, 2050, 2060])
            }
        }
    }

    @Test("Turning off include-existing means zero existing bonds and cash")
    func startFreshIsZeroExisting() {
        let withExisting = run(includeExisting: false, existing: realBonds())
        let withoutExisting = run(includeExisting: false, existing: [])

        #expect(withExisting == withoutExisting)
        #expect(withExisting.checkpoint(for: 2040)?.activeFace.minorUnits ?? -1 > 0)
    }

    // MARK: - Capped policy

    @Test("The capped ladder plateaus at roughly six million of face and piles up cash")
    func cappedLadderPlateaus() throws {
        let include = run(includeExisting: true, investExcessCoupons: false)
        let fresh = run(includeExisting: false, investExcessCoupons: false)

        let include2050 = try #require(include.checkpoint(for: 2050))
        let include2060 = try #require(include.checkpoint(for: 2060))
        let fresh2050 = try #require(fresh.checkpoint(for: 2050))
        let fresh2060 = try #require(fresh.checkpoint(for: 2060))

        #expect((550_000_000...650_000_000).contains(include2050.activeFace.minorUnits))
        #expect((550_000_000...650_000_000).contains(include2060.activeFace.minorUnits))
        #expect((550_000_000...650_000_000).contains(fresh2050.activeFace.minorUnits))
        #expect((550_000_000...650_000_000).contains(fresh2060.activeFace.minorUnits))

        #expect(include2050.couponCash.minorUnits > 0)
        #expect(include2060.couponCash.minorUnits > include2050.couponCash.minorUnits)
        #expect(fresh2060.couponCash.minorUnits > 0)

        #expect(isIn(include.checkpoint(for: 2040)?.totalValue, 4_900_000, 5_150_000))
        #expect(isIn(include2050.totalValue, 10_900_000, 11_300_000))
        #expect(isIn(include2060.totalValue, 17_200_000, 17_900_000))
        #expect(isIn(fresh.checkpoint(for: 2040)?.totalValue, 4_500_000, 4_700_000))
        #expect(isIn(fresh2050.totalValue, 10_300_000, 10_650_000))
        #expect(isIn(fresh2060.totalValue, 16_700_000, 17_200_000))
    }

    @Test("Investing excess coupons removes the plateau and raises the value")
    func excessCouponsRemovePlateau() throws {
        let capped = run(includeExisting: true, investExcessCoupons: false)
        let excess = run(includeExisting: true, investExcessCoupons: true)

        let capped2060 = try #require(capped.checkpoint(for: 2060))
        let excess2060 = try #require(excess.checkpoint(for: 2060))

        #expect(excess2060.activeFace.minorUnits > capped2060.activeFace.minorUnits * 3)
        #expect(excess2060.totalValue.minorUnits > capped2060.totalValue.minorUnits * 2)
        #expect(excess.unusedCouponCash.minorUnits < capped.unusedCouponCash.minorUnits / 4)
        #expect(excess.totalNewCash.minorUnits < capped.totalNewCash.minorUnits * 2)

        #expect(isIn(excess.checkpoint(for: 2040)?.totalValue, 5_100_000, 5_350_000))
        #expect(isIn(excess.checkpoint(for: 2050)?.totalValue, 14_700_000, 15_300_000))
        #expect(isIn(excess2060.totalValue, 42_000_000, 44_000_000))

        let freshExcess = run(includeExisting: false, investExcessCoupons: true)
        #expect(isIn(freshExcess.checkpoint(for: 2040)?.totalValue, 4_550_000, 4_750_000))
        #expect(isIn(freshExcess.checkpoint(for: 2050)?.totalValue, 13_000_000, 13_600_000))
        #expect(isIn(freshExcess.checkpoint(for: 2060)?.totalValue, 37_200_000, 39_000_000))
    }

    @Test("Existing bonds reduce the new cash and bring self-funding forward")
    func includeExistingChangesTheCashPlan() throws {
        let include = run(includeExisting: true, investExcessCoupons: false)
        let fresh = run(includeExisting: false, investExcessCoupons: false)

        let include2040 = try #require(include.checkpoint(for: 2040))
        let fresh2040 = try #require(fresh.checkpoint(for: 2040))

        #expect(include.totalNewCash.minorUnits < fresh.totalNewCash.minorUnits)
        #expect(include.couponFundedPurchases.minorUnits > fresh.couponFundedPurchases.minorUnits)
        #expect(include2040.activeFace.minorUnits > fresh2040.activeFace.minorUnits)
        #expect(include2040.totalValue.minorUnits > fresh2040.totalValue.minorUnits)
        #expect((include.selfFundingYear ?? Int.max) <= (fresh.selfFundingYear ?? Int.max))
        #expect(include.selfFundingYear == 2034)
        #expect(fresh.selfFundingYear == 2036)
    }

    @Test("Selecting the excess-coupon policy changes the 2060 value")
    func policyChangesThe2060Value() throws {
        let capped = run(includeExisting: true, investExcessCoupons: false)
        let excess = run(includeExisting: true, investExcessCoupons: true)

        let capped2060 = try #require(capped.checkpoint(for: 2060))
        let excess2060 = try #require(excess.checkpoint(for: 2060))

        #expect(capped2060.totalValue.minorUnits != excess2060.totalValue.minorUnits)
        #expect(excess2060.totalValue.minorUnits > capped2060.totalValue.minorUnits)
        #expect((capped2060.totalValue.minorUnits * 2) < excess2060.totalValue.minorUnits)
        #expect(capped2060.couponCash.minorUnits > excess2060.couponCash.minorUnits)
        #expect(capped.assumptions.contains { $0.contains("left uninvested") })
        #expect(excess.assumptions.contains { $0.contains("excess is invested") })
    }

    @Test("New cash is about 1.10M with existing bonds and 1.46M fresh")
    func newCashReference() {
        let include = run(includeExisting: true, investExcessCoupons: false)
        let fresh = run(includeExisting: false, investExcessCoupons: false)

        #expect(isIn(include.totalNewCash, 1_050_000, 1_170_000))
        #expect(isIn(fresh.totalNewCash, 1_400_000, 1_520_000))
        #expect(include.unusedCouponCash.minorUnits > 1_000_000_000)
        #expect(fresh.unusedCouponCash.minorUnits > 1_000_000_000)
    }

    @Test("The disclaimer and assumptions are explicit about the model")
    func disclaimerAndAssumptions() {
        #expect(InvestmentScenario.disclaimer.contains("not financial advice"))
        #expect(InvestmentScenario.disclaimer.contains("inflation"))
        #expect(InvestmentScenario.disclaimer.contains("licensed financial adviser"))

        let capped = run(includeExisting: true, investExcessCoupons: false)
        #expect(capped.assumptions.contains { $0.contains("inflation") })
        #expect(capped.assumptions.contains { $0.contains("Excess coupon cash is left uninvested") })

        let excess = run(includeExisting: true, investExcessCoupons: true)
        #expect(excess.assumptions.contains { $0.contains("excess is invested") })

        let fresh = run(includeExisting: false, investExcessCoupons: false)
        #expect(fresh.assumptions.contains { $0.contains("Start fresh") })
    }

    // MARK: - Sensitivity

    @Test("Sensitivity exposes 8%, 10% and 12% gross with their net rates")
    func sensitivityRates() {
        let results = InvestmentScenarioEngine.runSensitivity(
            scenario(),
            existingInvestments: realBonds()
        )

        #expect(results.map(\.grossRateBasisPoints) == [800, 1000, 1200])
        #expect(results.map(\.netRateBasisPoints) == [720, 900, 1080])

        let at2040 = results.compactMap { $0.checkpoint(for: 2040)?.totalValue.minorUnits }
        #expect(at2040.count == 3)
        #expect(at2040 == at2040.sorted())
        #expect((at2040.first ?? Int64.max) < (at2040.last ?? Int64.min))

        #expect(isIn(results[0].checkpoint(for: 2040)?.totalValue, 4_450_000, 4_600_000))
        #expect(isIn(results[0].checkpoint(for: 2050)?.totalValue, 8_500_000, 8_800_000))
        #expect(isIn(results[0].checkpoint(for: 2060)?.totalValue, 12_700_000, 13_200_000))

        #expect(isIn(results[1].checkpoint(for: 2040)?.totalValue, 4_650_000, 4_800_000))
        #expect(isIn(results[1].checkpoint(for: 2050)?.totalValue, 9_650_000, 9_950_000))
        #expect(isIn(results[1].checkpoint(for: 2060)?.totalValue, 14_950_000, 15_450_000))

        #expect(isIn(results[2].checkpoint(for: 2040)?.totalValue, 4_950_000, 5_120_000))
        #expect(isIn(results[2].checkpoint(for: 2050)?.totalValue, 10_950_000, 11_300_000))
        #expect(isIn(results[2].checkpoint(for: 2060)?.totalValue, 17_300_000, 17_850_000))
    }

    @Test("Investing excess coupons is far more rate-sensitive than the capped plan")
    func excessSensitivity() {
        let results = InvestmentScenarioEngine.runSensitivity(
            scenario(investExcessCoupons: true),
            existingInvestments: realBonds()
        )

        #expect(results.map(\.grossRateBasisPoints) == [800, 1000, 1200])

        let at2060 = results.compactMap { $0.checkpoint(for: 2060)?.totalValue.minorUnits }
        #expect(at2060.count == 3)
        #expect(at2060 == at2060.sorted())
        #expect((at2060.last ?? 0) > (at2060.first ?? 0) * 2)

        #expect(isIn(results[0].checkpoint(for: 2060)?.totalValue, 18_800_000, 19_500_000))
        #expect(isIn(results[1].checkpoint(for: 2060)?.totalValue, 27_800_000, 28_700_000))
        #expect(isIn(results[2].checkpoint(for: 2060)?.totalValue, 42_000_000, 44_000_000))
    }

    @Test("The slider rate is added to the sensitivity band when it differs")
    func sliderRateJoinsSensitivity() {
        let results = InvestmentScenarioEngine.runSensitivity(
            scenario(rate: 1500),
            existingInvestments: realBonds()
        )

        #expect(results.map(\.grossRateBasisPoints) == [800, 1000, 1200, 1500])
        #expect(results.last?.netRateBasisPoints == 1350)
    }
}
