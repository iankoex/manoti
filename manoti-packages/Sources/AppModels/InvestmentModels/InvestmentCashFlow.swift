//
//  InvestmentCashFlow.swift
//  AppModels
//

import Foundation
import SwiftData

/// A dated investment cash movement: a purchase, coupon, redemption, tax row, interest
/// payment, contribution or withdrawal.
///
/// Scheduled rows are generated from the investment terms; paid rows store what actually
/// happened and can point at the linked ledger entry.
@Model
public final class InvestmentCashFlow {
    public var id: UUID = UUID()
    public var kindRaw: String = InvestmentCashFlowKind.coupon.rawValue
    public var date: Date = Date()
    public var grossMinor: Int64 = 0
    public var taxMinor: Int64 = 0
    public var netMinor: Int64 = 0
    public var statusRaw: String = InvestmentCashFlowStatus.scheduled.rawValue
    public var note: String = ""
    public var isSoftDeleted: Bool = false
    public var createdAt: Date = Date()

    public var investment: Investment?
    public var ledgerEntry: LedgerEntry?

    public init(
        kind: InvestmentCashFlowKind,
        date: Date = Date(),
        grossMinor: Int64 = 0,
        taxMinor: Int64 = 0,
        netMinor: Int64? = nil,
        status: InvestmentCashFlowStatus = .scheduled,
        note: String = ""
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.date = date
        self.grossMinor = grossMinor
        self.taxMinor = taxMinor
        self.netMinor = netMinor ?? (grossMinor - taxMinor)
        self.statusRaw = status.rawValue
        self.note = note
        self.createdAt = Date()
    }

    public var kind: InvestmentCashFlowKind {
        get { InvestmentCashFlowKind(rawValue: kindRaw) ?? .coupon }
        set { kindRaw = newValue.rawValue }
    }

    public var status: InvestmentCashFlowStatus {
        get { InvestmentCashFlowStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    public var currency: Currency {
        investment?.currency ?? CurrencyCatalog.defaultCurrency
    }

    public var gross: Money {
        Money(minorUnits: grossMinor, currency: currency)
    }

    public var tax: Money {
        Money(minorUnits: taxMinor, currency: currency)
    }

    public var net: Money {
        Money(minorUnits: netMinor, currency: currency)
    }
}
