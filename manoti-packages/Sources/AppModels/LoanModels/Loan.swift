//
//  Loan.swift
//  AppModels
//

import Foundation
import SwiftData

/// A loan the user gave or received.
///
/// Cash moves through ordinary `LedgerEntry` rows linked here; the outstanding balance is
/// always derived and never stored.
@Model
public final class Loan {
    public var id: UUID = UUID()
    public var directionRaw: String = LoanDirection.lent.rawValue
    public var counterparty: String = ""
    public var principalMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var startedAt: Date = Date()
    public var dueAt: Date?
    public var note: String = ""
    public var statusRaw: String = LoanStatus.open.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var isSoftDeleted: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.loan)
    public var entries: [LedgerEntry]?

    public init(
        direction: LoanDirection,
        counterparty: String,
        principalMinor: Int64,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        startedAt: Date = Date(),
        dueAt: Date? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.directionRaw = direction.rawValue
        self.counterparty = counterparty
        self.principalMinor = principalMinor
        self.currencyCode = currencyCode
        self.startedAt = startedAt
        self.dueAt = dueAt
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var direction: LoanDirection {
        get { LoanDirection(rawValue: directionRaw) ?? .lent }
        set { directionRaw = newValue.rawValue }
    }

    public var status: LoanStatus {
        get { LoanStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    public var outstandingMinor: Int64 {
        LoanBalance.outstandingMinor(for: self)
    }

    public var outstanding: Money {
        Money(minorUnits: outstandingMinor, currency: currency)
    }
}
