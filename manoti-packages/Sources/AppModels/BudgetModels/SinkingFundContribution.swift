//
//  SinkingFundContribution.swift
//  AppModels
//

import Foundation
import SwiftData

/// One dated deposit into a sinking fund.
@Model
public final class SinkingFundContribution {
    public var id: UUID = UUID()
    public var amountMinor: Int64 = 0
    public var occurredAt: Date = Date()
    public var note: String = ""
    public var createdAt: Date = Date()

    public var fund: SinkingFund?
    public var account: Account?

    public init(
        fund: SinkingFund? = nil,
        amountMinor: Int64 = 0,
        occurredAt: Date = Date(),
        account: Account? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.fund = fund
        self.amountMinor = amountMinor
        self.occurredAt = occurredAt
        self.account = account
        self.note = note
        self.createdAt = Date()
    }

    public var amount: Money {
        Money(
            minorUnits: amountMinor,
            currency: fund?.currency ?? CurrencyCatalog.defaultCurrency
        )
    }
}
