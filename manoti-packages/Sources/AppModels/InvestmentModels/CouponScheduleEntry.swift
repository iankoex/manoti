//
//  CouponScheduleEntry.swift
//  AppModels
//

import Foundation

/// One expected coupon on an investment's schedule.
nonisolated public struct CouponScheduleEntry: Hashable, Sendable, Identifiable {
    public let date: Date
    public let grossMinor: Int64
    public let taxMinor: Int64
    public let netMinor: Int64
    public let status: InvestmentCashFlowStatus

    public var id: Date { date }

    public init(
        date: Date,
        grossMinor: Int64,
        taxMinor: Int64,
        netMinor: Int64,
        status: InvestmentCashFlowStatus = .scheduled
    ) {
        self.date = date
        self.grossMinor = grossMinor
        self.taxMinor = taxMinor
        self.netMinor = netMinor
        self.status = status
    }

    public func gross(in currency: Currency) -> Money {
        Money(minorUnits: grossMinor, currency: currency)
    }

    public func tax(in currency: Currency) -> Money {
        Money(minorUnits: taxMinor, currency: currency)
    }

    public func net(in currency: Currency) -> Money {
        Money(minorUnits: netMinor, currency: currency)
    }
}
