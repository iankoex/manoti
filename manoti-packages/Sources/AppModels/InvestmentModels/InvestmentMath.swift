//
//  InvestmentMath.swift
//  AppModels
//

import Foundation

/// Pure investment arithmetic: coupon schedules, withholding, accrued interest, money
/// market compounding and illustrative reinvestment projections.
///
/// All money is exact `Int64` minor units. Rates are basis points and use `Decimal` where a
/// CBK quote has three decimal places (12.857%). Rounding is half-even at the minor-unit
/// boundary, matching `Money`.
nonisolated public enum InvestmentMath {
    public static let defaultCouponPeriodDays = 182
    public static let dayCountBasisDays = 365
    public static let cleanPriceScale: Int64 = 10_000

    public static let defaultReinvestmentRateBasisPoints = 1200
    public static let defaultWithholdingTaxBasisPoints = 1000

    /// UTC Gregorian calendar used for schedule generation.
    ///
    /// Tests and stored prospectus dates use the same convention, so a 182-day grid is
    /// stable regardless of the device time zone.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    // MARK: - Schedule

    /// The remaining coupon dates for a bond.
    ///
    /// Prospectus overrides win when present. Otherwise dates are generated from
    /// `firstCouponDate` by adding `couponPeriodDays` (182) until maturity. Each generated
    /// date is moved to the next business day when it falls on a Saturday or Sunday. No
    /// Kenyan public-holiday calendar is applied, so an exchange holiday needs an explicit
    /// prospectus override. The original 182-day grid is retained while generating; only
    /// the emitted dates are adjusted, so a weekend shift never accumulates.
    ///
    /// `startDate` defaults to now, so the result is the *remaining* schedule. Pass the
    /// purchase date to build the full schedule from the purchase.
    public static func couponSchedule(
        for investment: Investment,
        from startDate: Date? = nil,
        calendar: Calendar = InvestmentMath.calendar
    ) -> [CouponScheduleEntry] {
        guard investment.type == .treasuryBond else {
            return []
        }

        let start = startDate ?? Date()
        let startDay = calendar.startOfDay(for: start)
        let maturityDay = investment.maturityDate.map { calendar.startOfDay(for: $0) }

        let dates: [Date]
        if !investment.couponDateOverrides.isEmpty {
            dates = investment.couponDateOverrides.sorted()
        } else {
            dates = generatedCouponDates(for: investment, calendar: calendar)
        }

        let gross = grossCouponMinor(for: investment)
        let tax = taxMinor(for: investment)
        let net = gross - tax

        return
            dates
            .filter { date in
                let day = calendar.startOfDay(for: date)
                guard day >= startDay else {
                    return false
                }

                if let maturityDay, day > maturityDay {
                    return false
                }

                return true
            }
            .map { date in
                CouponScheduleEntry(
                    date: date,
                    grossMinor: gross,
                    taxMinor: tax,
                    netMinor: net,
                    status: .scheduled
                )
            }
    }

    private static func generatedCouponDates(for investment: Investment, calendar: Calendar) -> [Date] {
        guard let firstCouponDate = investment.firstCouponDate, let maturityDate = investment.maturityDate else {
            return []
        }

        let maturityDay = calendar.startOfDay(for: maturityDate)
        let period = max(1, investment.couponPeriodDays)
        var rawDate = firstCouponDate
        var dates: [Date] = []

        while calendar.startOfDay(for: rawDate) <= maturityDay {
            dates.append(adjustToBusinessDay(rawDate, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: period, to: rawDate) else {
                break
            }
            rawDate = next
        }

        return dates
    }

    /// Moves a weekend date to the following Monday.
    ///
    /// Weekdays are unchanged.
    static func adjustToBusinessDay(_ date: Date, calendar: Calendar = InvestmentMath.calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
            case 1:
                return calendar.date(byAdding: .day, value: 1, to: date) ?? date
            case 7:
                return calendar.date(byAdding: .day, value: 2, to: date) ?? date
            default:
                return date
        }
    }

    // MARK: - Coupons

    public static func grossCouponMinor(for investment: Investment) -> Int64 {
        grossCouponMinor(
            nominalMinor: investment.nominalMinor,
            couponRateBasisPoints: investment.couponRateBasisPoints
        )
    }

    /// Semi-annual gross coupon: `nominal × annual rate ÷ 2`.
    public static func grossCouponMinor(nominalMinor: Int64, couponRateBasisPoints: Decimal) -> Int64 {
        rounded(Decimal(nominalMinor) * couponRateBasisPoints / Decimal(20_000))
    }

    public static func taxMinor(for investment: Investment) -> Int64 {
        taxMinor(
            grossMinor: grossCouponMinor(for: investment),
            withholdingTaxBasisPoints: investment.withholdingTaxBasisPoints,
            taxExempt: investment.taxExempt
        )
    }

    public static func taxMinor(
        grossMinor: Int64,
        withholdingTaxBasisPoints: Int,
        taxExempt: Bool = false
    ) -> Int64 {
        guard !taxExempt else {
            return 0
        }

        let rate = min(max(withholdingTaxBasisPoints, 0), 10_000)
        return rounded(Decimal(grossMinor) * Decimal(rate) / Decimal(10_000))
    }

    public static func netCouponMinor(for investment: Investment) -> Int64 {
        let gross = grossCouponMinor(for: investment)
        return gross - taxMinor(for: investment)
    }

    public static func netCouponMinor(
        nominalMinor: Int64,
        couponRateBasisPoints: Decimal,
        withholdingTaxBasisPoints: Int,
        taxExempt: Bool = false
    ) -> Int64 {
        let gross = grossCouponMinor(nominalMinor: nominalMinor, couponRateBasisPoints: couponRateBasisPoints)
        return gross
            - taxMinor(
                grossMinor: gross,
                withholdingTaxBasisPoints: withholdingTaxBasisPoints,
                taxExempt: taxExempt
            )
    }

    /// Every remaining net coupon to maturity, from `startDate` (default: now).
    public static func totalNetCoupons(for investment: Investment, from startDate: Date? = nil) -> Int64 {
        couponSchedule(for: investment, from: startDate).reduce(into: Int64(0)) { total, entry in
            total += entry.netMinor
        }
    }

    // MARK: - Accrued interest and dirty price

    /// Accrued interest on a reopened bond using an actual/365 day count.
    ///
    /// The prospectus amount is authoritative when the broker statement supplies one; this
    /// helper is for a computed estimate and for checking it.
    public static func accruedInterestMinor(
        nominalMinor: Int64,
        couponRateBasisPoints: Decimal,
        daysSinceLastCoupon: Int,
        dayCountBasisDays: Int = InvestmentMath.dayCountBasisDays
    ) -> Int64 {
        guard daysSinceLastCoupon > 0, dayCountBasisDays > 0 else {
            return 0
        }

        let value =
            Decimal(nominalMinor) * couponRateBasisPoints / Decimal(10_000)
            * Decimal(daysSinceLastCoupon) / Decimal(dayCountBasisDays)
        return rounded(value)
    }

    /// The cash-equivalent of a clean price quoted per 100 nominal.
    public static func cleanPriceMinor(nominalMinor: Int64, pricePer100: Decimal) -> Int64 {
        rounded(Decimal(nominalMinor) * pricePer100 / Decimal(100))
    }

    /// Stores a per-100 clean price at `cleanPriceScale`.
    public static func scaledCleanPrice(pricePer100: Decimal) -> Int64 {
        rounded(pricePer100 * Decimal(cleanPriceScale))
    }

    public static func pricePer100(fromScaled scaled: Int64) -> Decimal {
        Decimal(scaled) / Decimal(cleanPriceScale)
    }

    /// Dirty cash = clean price plus accrued interest.
    public static func dirtyPriceMinor(cleanPriceMinor: Int64, accruedInterestMinor: Int64) -> Int64 {
        cleanPriceMinor + accruedInterestMinor
    }

    // MARK: - Money market

    /// Daily compounding on the after-tax annual rate:
    /// `principal × (1 + net annual rate ÷ 365)^days`.
    public static func moneyMarketValueMinor(
        principalMinor: Int64,
        annualRateBasisPoints: Decimal,
        withholdingTaxBasisPoints: Int,
        taxExempt: Bool = false,
        days: Int
    ) -> Int64 {
        guard principalMinor != 0 else {
            return 0
        }

        guard days > 0 else {
            return principalMinor
        }

        let taxRate = taxExempt ? 0 : min(max(withholdingTaxBasisPoints, 0), 10_000)
        let netAnnualRate = annualRateBasisPoints * (Decimal(10_000 - taxRate) / Decimal(10_000))
        let dailyRate = netAnnualRate / Decimal(10_000) / Decimal(dayCountBasisDays)
        let value = Decimal(principalMinor) * power(Decimal(1) + dailyRate, days)
        return rounded(value)
    }

    public static func moneyMarketDays(
        for investment: Investment, asOf date: Date, calendar: Calendar = InvestmentMath.calendar
    ) -> Int {
        let start = investment.startDate ?? investment.purchaseDate
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Cost basis until a manual market value exists; daily-compounded value for money
    /// market accounts; zero for pending and matured rows.
    public static func currentValueMinor(
        for investment: Investment,
        asOf date: Date = Date(),
        calendar: Calendar = InvestmentMath.calendar
    ) -> Int64 {
        guard investment.isActive else {
            return 0
        }

        if let marketValueMinor = investment.marketValueMinor {
            return marketValueMinor
        }

        switch investment.type {
            case .moneyMarket:
                return moneyMarketValueMinor(
                    principalMinor: investment.nominalMinor,
                    annualRateBasisPoints: investment.annualRateBasisPoints,
                    withholdingTaxBasisPoints: investment.withholdingTaxBasisPoints,
                    taxExempt: investment.taxExempt,
                    days: moneyMarketDays(for: investment, asOf: date, calendar: calendar)
                )
            case .treasuryBond, .treasuryBill:
                return investment.cashInvestedMinor
        }
    }

    // MARK: - Projection

    /// Projects net coupons at the editable reinvestment rate (not the bond's coupon rate).
    ///
    /// The default 12% gross becomes 10.8% net at 10% withholding. Coupons are compounded
    /// semi-annually at `net rate ÷ 2`; each coupon compounds for the number of complete
    /// 182-day periods between its payment date and the target date.
    public static func projection(
        for investment: Investment,
        reinvestmentRateBasisPoints: Int = defaultReinvestmentRateBasisPoints,
        horizonYears: Int = 20,
        taxRateBasisPoints: Int? = nil,
        asOf: Date = Date(),
        calendar: Calendar = InvestmentMath.calendar
    ) -> InvestmentProjection {
        let currency = investment.currency
        let taxRate = min(max(taxRateBasisPoints ?? investment.effectiveWithholdingTaxBasisPoints, 0), 10_000)
        let grossRate = max(0, reinvestmentRateBasisPoints)
        let netRate = grossRate * (10_000 - taxRate) / 10_000
        let assumptions = [
            "Illustrative only: constant rate, no fees, no default.",
            "Net coupons are reinvested in full.",
            "The projection uses the configured reinvestment rate, not the coupon rate.",
        ]

        let totalNet = totalNetCoupons(for: investment, from: asOf)
        let holdToMaturity = investment.nominalMinor + totalNet
        let years = max(0, horizonYears)
        let horizonDate = calendar.date(byAdding: .year, value: years, to: asOf) ?? asOf

        guard investment.type == .treasuryBond, investment.maturityDate != nil else {
            let value = currentValueMinor(for: investment, asOf: asOf, calendar: calendar)

            return InvestmentProjection(
                holdToMaturity: Money(minorUnits: value, currency: currency),
                reinvestedAtMaturity: Money(minorUnits: value, currency: currency),
                horizonValue: Money(minorUnits: value, currency: currency),
                totalNetCoupons: Money(minorUnits: 0, currency: currency),
                horizonYears: years,
                grossReinvestmentRateBasisPoints: grossRate,
                netReinvestmentRateBasisPoints: netRate,
                taxRateBasisPoints: taxRate,
                assumptions: assumptions
            )
        }

        let schedule = couponSchedule(for: investment, from: asOf, calendar: calendar)
        let periodRate = Decimal(netRate) / Decimal(20_000)
        let periodDays = max(1, investment.couponPeriodDays)

        let reinvestedAtMaturity = compoundedValue(
            schedule: schedule,
            principalMinor: investment.nominalMinor,
            maturity: investment.maturityDate,
            target: investment.maturityDate,
            periodRate: periodRate,
            periodDays: periodDays,
            calendar: calendar
        )

        let horizonValue = compoundedValue(
            schedule: schedule,
            principalMinor: investment.nominalMinor,
            maturity: investment.maturityDate,
            target: horizonDate,
            periodRate: periodRate,
            periodDays: periodDays,
            calendar: calendar
        )

        return InvestmentProjection(
            holdToMaturity: Money(minorUnits: holdToMaturity, currency: currency),
            reinvestedAtMaturity: Money(minorUnits: reinvestedAtMaturity, currency: currency),
            horizonValue: Money(minorUnits: horizonValue, currency: currency),
            totalNetCoupons: Money(minorUnits: totalNet, currency: currency),
            horizonYears: years,
            grossReinvestmentRateBasisPoints: grossRate,
            netReinvestmentRateBasisPoints: netRate,
            taxRateBasisPoints: taxRate,
            assumptions: assumptions
        )
    }

    private static func compoundedValue(
        schedule: [CouponScheduleEntry],
        principalMinor: Int64,
        maturity: Date?,
        target: Date?,
        periodRate: Decimal,
        periodDays: Int,
        calendar: Calendar
    ) -> Int64 {
        guard let target else {
            return 0
        }

        let targetDay = calendar.startOfDay(for: target)
        var total = Decimal(0)

        for entry in schedule {
            let entryDay = calendar.startOfDay(for: entry.date)
            guard entryDay <= targetDay else {
                continue
            }

            let days = max(0, calendar.dateComponents([.day], from: entryDay, to: targetDay).day ?? 0)
            let periods = days / periodDays
            total += Decimal(entry.netMinor) * power(Decimal(1) + periodRate, periods)
        }

        // Principal is only available once the investment has matured by the target date.
        if let maturity, calendar.startOfDay(for: maturity) <= targetDay {
            total += Decimal(principalMinor)
        }

        return rounded(total)
    }

    // MARK: - Helpers

    private static func power(_ base: Decimal, _ exponent: Int) -> Decimal {
        guard exponent > 0 else {
            return 1
        }

        var result = Decimal(1)
        var factor = base
        var remaining = exponent

        while remaining > 0 {
            if remaining % 2 == 1 {
                result *= factor
            }
            factor *= factor
            remaining /= 2
        }

        return result
    }

    private static func rounded(_ value: Decimal) -> Int64 {
        NSDecimalNumber(decimal: value)
            .rounding(accordingToBehavior: Money.bankersHandler)
            .int64Value
    }
}
