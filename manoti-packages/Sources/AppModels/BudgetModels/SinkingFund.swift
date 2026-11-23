//
//  SinkingFund.swift
//  AppModels
//

import Foundation
import SwiftData

/// Money set aside for an irregular future cost, funded by dated contributions.
@Model
public final class SinkingFund {
    public var id: UUID = UUID()
    public var name: String = ""
    public var targetMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var monthlyAccrualMinor: Int64 = 0
    public var targetDate: Date?
    public var note: String = ""
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    public var category: SpendingCategory?
    public var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \SinkingFundContribution.fund)
    public var contributions: [SinkingFundContribution]?

    public init(
        name: String,
        targetMinor: Int64 = 0,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        monthlyAccrualMinor: Int64 = 0,
        targetDate: Date? = nil,
        category: SpendingCategory? = nil,
        account: Account? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.targetMinor = targetMinor
        self.currencyCode = currencyCode
        self.monthlyAccrualMinor = monthlyAccrualMinor
        self.targetDate = targetDate
        self.category = category
        self.account = account
        self.note = note
        self.createdAt = Date()
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    public var target: Money {
        Money(minorUnits: targetMinor, currency: currency)
    }

    /// Total contributed so far, derived from the contribution rows.
    public var fundedMinor: Int64 {
        (contributions ?? []).reduce(0) { $0 + $1.amountMinor }
    }

    public var funded: Money {
        Money(minorUnits: fundedMinor, currency: currency)
    }
}
