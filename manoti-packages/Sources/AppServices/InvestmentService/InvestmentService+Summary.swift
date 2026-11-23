//
//  InvestmentService+Summary.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

nonisolated public struct InvestmentSummary: Equatable, Sendable {
    public struct NextCoupon: Equatable, Sendable {
        public let date: Date
        public let gross: Money
        public let tax: Money
        public let net: Money

        public init(date: Date, gross: Money, tax: Money, net: Money) {
            self.date = date
            self.gross = gross
            self.tax = tax
            self.net = net
        }
    }

    public let totalNominal: Money
    public let cashInvested: Money
    public let nextCoupon: NextCoupon?
    public let totalNetCoupons: Money
    public let projectedValue: Money
    public let missingRates: [String]

    public init(
        totalNominal: Money,
        cashInvested: Money,
        nextCoupon: NextCoupon?,
        totalNetCoupons: Money,
        projectedValue: Money,
        missingRates: [String]
    ) {
        self.totalNominal = totalNominal
        self.cashInvested = cashInvested
        self.nextCoupon = nextCoupon
        self.totalNetCoupons = totalNetCoupons
        self.projectedValue = projectedValue
        self.missingRates = missingRates
    }
}

extension InvestmentService {
    /// Active holdings only: pending settlements and matured rows are excluded.
    ///
    /// A missing rate is marked and converted 1:1 in major units, exactly like account
    /// balances and loan summaries.
    public func summary(displayCurrency: Currency, asOf: Date = Date()) throws -> InvestmentSummary {
        let book = try rateBook()
        let defaultRate = try defaultReinvestmentRateBasisPoints()
        let investments = try fetchInvestments(includeMatured: false).filter { $0.status == .active }

        var nominal: Int64 = 0
        var invested: Int64 = 0
        var netCoupons: Int64 = 0
        var projected: Int64 = 0
        var missing: Set<String> = []
        var nextCoupon: InvestmentSummary.NextCoupon?

        for investment in investments {
            nominal += converted(
                investment.nominalMinor,
                from: investment.currency,
                to: displayCurrency,
                on: asOf,
                book: book,
                missing: &missing
            )
            invested += converted(
                investment.cashInvestedMinor,
                from: investment.currency,
                to: displayCurrency,
                on: asOf,
                book: book,
                missing: &missing
            )

            let schedule = InvestmentMath.couponSchedule(for: investment, from: asOf)
            for entry in schedule {
                netCoupons += converted(
                    entry.netMinor,
                    from: investment.currency,
                    to: displayCurrency,
                    on: asOf,
                    book: book,
                    missing: &missing
                )
            }

            if let first = schedule.first {
                if nextCoupon == nil || first.date < (nextCoupon?.date ?? first.date) {
                    nextCoupon = InvestmentSummary.NextCoupon(
                        date: first.date,
                        gross: Money(
                            minorUnits: converted(
                                first.grossMinor,
                                from: investment.currency,
                                to: displayCurrency,
                                on: asOf,
                                book: book,
                                missing: &missing
                            ),
                            currency: displayCurrency
                        ),
                        tax: Money(
                            minorUnits: converted(
                                first.taxMinor,
                                from: investment.currency,
                                to: displayCurrency,
                                on: asOf,
                                book: book,
                                missing: &missing
                            ),
                            currency: displayCurrency
                        ),
                        net: Money(
                            minorUnits: converted(
                                first.netMinor,
                                from: investment.currency,
                                to: displayCurrency,
                                on: asOf,
                                book: book,
                                missing: &missing
                            ),
                            currency: displayCurrency
                        )
                    )
                }
            }

            let valueMinor: Int64
            if investment.type == .treasuryBond, investment.maturityDate != nil {
                let projection = InvestmentMath.projection(
                    for: investment,
                    reinvestmentRateBasisPoints: investment.reinvestmentRateBasisPoints ?? defaultRate,
                    horizonYears: 0,
                    taxRateBasisPoints: investment.effectiveWithholdingTaxBasisPoints,
                    asOf: asOf
                )
                valueMinor = projection.reinvestedAtMaturity.minorUnits
            } else {
                valueMinor = investment.currentValueMinor(asOf: asOf)
            }

            projected += converted(
                valueMinor,
                from: investment.currency,
                to: displayCurrency,
                on: asOf,
                book: book,
                missing: &missing
            )
        }

        return InvestmentSummary(
            totalNominal: Money(minorUnits: nominal, currency: displayCurrency),
            cashInvested: Money(minorUnits: invested, currency: displayCurrency),
            nextCoupon: nextCoupon,
            totalNetCoupons: Money(minorUnits: netCoupons, currency: displayCurrency),
            projectedValue: Money(minorUnits: projected, currency: displayCurrency),
            missingRates: missing.sorted()
        )
    }

    private func rateBook() throws -> ExchangeRateBook {
        let records = try context.fetch(
            FetchDescriptor<ExchangeRateRecord>(sortBy: [SortDescriptor(\ExchangeRateRecord.asOf, order: .reverse)])
        )
        return ExchangeRateBook(records: records)
    }

    private func defaultReinvestmentRateBasisPoints() throws -> Int {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        if let settings = try context.fetch(descriptor).first {
            return settings.reinvestmentRateBasisPoints
        }

        return AppSettings.defaultReinvestmentRateBasisPoints
    }

    private func converted(
        _ minorUnits: Int64,
        from currency: Currency,
        to displayCurrency: Currency,
        on date: Date,
        book: ExchangeRateBook,
        missing: inout Set<String>
    ) -> Int64 {
        let money = Money(minorUnits: minorUnits, currency: currency)

        if let converted = book.convert(money, to: displayCurrency, on: date) {
            return converted.minorUnits
        }

        missing.insert(currency.code)
        return fallback(money, to: displayCurrency).minorUnits
    }

    /// Reinterprets the major-unit amount in the display currency.
    private func fallback(_ money: Money, to currency: Currency) -> Money {
        Money(decimal: money.decimalValue, currency: currency) ?? .zero(in: currency)
    }
}
