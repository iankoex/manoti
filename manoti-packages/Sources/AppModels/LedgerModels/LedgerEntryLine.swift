//
//  LedgerEntryLine.swift
//  AppModels
//

import Foundation
import SwiftData

/// One attribution of a ledger entry: how much of the money went to a category and to tags.
///
/// A normal entry has exactly one line, so the line carries the category that used to live on
/// the entry. A split entry has several, and their amounts add up to the entry total.
@Model
public final class LedgerEntryLine {
    public var id: UUID = UUID()
    public var amountMinor: Int64 = 0
    public var sortIndex: Int = 0
    public var createdAt: Date = Date()

    public var entry: LedgerEntry?
    public var category: SpendingCategory?
    public var tags: [Tag]?

    public init(
        amountMinor: Int64,
        sortIndex: Int = 0,
        category: SpendingCategory? = nil,
        tags: [Tag] = []
    ) {
        self.id = UUID()
        self.amountMinor = amountMinor
        self.sortIndex = sortIndex
        self.category = category
        self.tags = tags
        self.createdAt = Date()
    }

    public var amount: Money {
        Money(minorUnits: amountMinor, currency: entry?.currency ?? CurrencyCatalog.defaultCurrency)
    }

    public var tagList: [Tag] {
        (tags ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
