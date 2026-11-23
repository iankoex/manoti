//
//  InvestmentProjection.swift
//  AppModels
//

import Foundation

/// An illustrative reinvestment projection at a constant, editable rate.
nonisolated public struct InvestmentProjection: Equatable, Sendable {
    /// Principal plus net coupons at maturity, before reinvestment.
    public let holdToMaturity: Money
    /// Principal plus net coupons reinvested until maturity.
    public let reinvestedAtMaturity: Money
    /// Value at the requested horizon, including principal only once it has matured.
    public let horizonValue: Money
    /// Every net coupon from the valuation date to maturity.
    public let totalNetCoupons: Money
    public let horizonYears: Int
    public let grossReinvestmentRateBasisPoints: Int
    public let netReinvestmentRateBasisPoints: Int
    public let taxRateBasisPoints: Int
    public let assumptions: [String]

    public init(
        holdToMaturity: Money,
        reinvestedAtMaturity: Money,
        horizonValue: Money,
        totalNetCoupons: Money,
        horizonYears: Int,
        grossReinvestmentRateBasisPoints: Int,
        netReinvestmentRateBasisPoints: Int,
        taxRateBasisPoints: Int,
        assumptions: [String]
    ) {
        self.holdToMaturity = holdToMaturity
        self.reinvestedAtMaturity = reinvestedAtMaturity
        self.horizonValue = horizonValue
        self.totalNetCoupons = totalNetCoupons
        self.horizonYears = horizonYears
        self.grossReinvestmentRateBasisPoints = grossReinvestmentRateBasisPoints
        self.netReinvestmentRateBasisPoints = netReinvestmentRateBasisPoints
        self.taxRateBasisPoints = taxRateBasisPoints
        self.assumptions = assumptions
    }
}
