//
//  SpendingCategory.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class SpendingCategory {
    public var id: UUID = UUID()
    public var name: String = ""
    public var symbolName: String = "circle"
    public var colorHex: String = "#8E8E93"
    public var isFixed: Bool = false
    public var monthlyDefaultMinor: Int64?
    public var keywords: String = ""
    public var sortIndex: Int = 0
    public var isArchived: Bool = false
    public var kindRaw: String = CategoryKind.expense.rawValue
    public var group: CategoryGroup?

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    public var transactions: [LedgerEntry]?

    @Relationship(deleteRule: .nullify, inverse: \MerchantMemory.category)
    public var merchantMemories: [MerchantMemory]?

    @Relationship(deleteRule: .nullify, inverse: \SmartRule.targetCategory)
    public var smartRules: [SmartRule]?

    @Relationship(deleteRule: .nullify, inverse: \Envelope.category)
    public var budgetEnvelopes: [Envelope]?

    @Relationship(deleteRule: .nullify, inverse: \SinkingFund.category)
    public var sinkingFunds: [SinkingFund]?

    public init(
        name: String,
        symbolName: String,
        colorHex: String,
        isFixed: Bool = false,
        keywords: String = "",
        sortIndex: Int = 0,
        kind: CategoryKind = .expense
    ) {
        self.id = UUID()
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.isFixed = isFixed
        self.keywords = keywords
        self.sortIndex = sortIndex
        self.kindRaw = kind.rawValue
    }

    public var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public var isIncome: Bool {
        kind == .income
    }

    public var keywordList: [String] {
        keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    public var monthlyDefault: Money? {
        guard let monthlyDefaultMinor else {
            return nil
        }

        return Money(minorUnits: monthlyDefaultMinor, currency: CurrencyCatalog.defaultCurrency)
    }
}
