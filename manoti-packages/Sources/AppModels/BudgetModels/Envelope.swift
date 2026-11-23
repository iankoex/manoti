//
//  Envelope.swift
//  AppModels
//

import Foundation
import SwiftData

/// A spending limit for one category during one budget period.
///
/// Limits are stored in the display currency at the time the envelope is created. One row
/// exists per category per period; the service upserts rather than inserting duplicates.
@Model
public final class Envelope {
    public var id: UUID = UUID()
    public var limitMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var rolloverEnabled: Bool = false
    public var note: String = ""
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    public var period: BudgetPeriod?
    public var category: SpendingCategory?

    @Relationship(deleteRule: .cascade, inverse: \BudgetAlert.envelope)
    public var alerts: [BudgetAlert]?

    public init(
        period: BudgetPeriod? = nil,
        category: SpendingCategory? = nil,
        limitMinor: Int64 = 0,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        rolloverEnabled: Bool = false,
        note: String = ""
    ) {
        self.id = UUID()
        self.period = period
        self.category = category
        self.limitMinor = limitMinor
        self.currencyCode = currencyCode
        self.rolloverEnabled = rolloverEnabled
        self.note = note
        self.createdAt = Date()
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    public var limit: Money {
        Money(minorUnits: limitMinor, currency: currency)
    }
}
