//
//  Goal.swift
//  AppModels
//

import Foundation
import SwiftData

/// A savings goal. An account-linked goal derives progress from the account balance; a
/// standalone goal tracks its progress through manual contributions.
@Model
public final class Goal {
    public var id: UUID = UUID()
    public var name: String = ""
    public var targetMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var targetDate: Date?
    public var note: String = ""
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    public var account: Account?

    public init(
        name: String,
        targetMinor: Int64 = 0,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        targetDate: Date? = nil,
        account: Account? = nil,
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.targetMinor = targetMinor
        self.currencyCode = currencyCode
        self.targetDate = targetDate
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

    /// Progress in minor units for an account-linked goal. Manual goals return zero here
    /// until the contributions flow lands.
    public var progressMinor: Int64 {
        account?.balance.minorUnits ?? 0
    }
}
