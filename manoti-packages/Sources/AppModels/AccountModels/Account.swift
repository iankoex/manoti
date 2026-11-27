//
//  Account.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class Account {
    public var id: UUID = UUID()
    public var name: String = ""
    public var kindRaw: String = AccountKind.bank.rawValue
    public var ownershipRaw: String = AccountOwnership.personal.rawValue
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var colorHex: String = "#2F80ED"
    public var symbolName: String = "building.columns"
    public var institution: String = ""
    public var note: String = ""
    public var isArchived: Bool = false
    public var sortIndex: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.account)
    public var transactions: [LedgerEntry]?

    @Relationship(deleteRule: .cascade, inverse: \AccountIdentifier.account)
    public var identifiers: [AccountIdentifier]?

    @Relationship(deleteRule: .nullify, inverse: \Transfer.fromAccount)
    public var transfersOut: [Transfer]?

    @Relationship(deleteRule: .nullify, inverse: \Transfer.toAccount)
    public var transfersIn: [Transfer]?

    @Relationship(deleteRule: .nullify, inverse: \MerchantMemory.account)
    public var merchantMemories: [MerchantMemory]?

    @Relationship(deleteRule: .nullify, inverse: \SinkingFund.account)
    public var sinkingFunds: [SinkingFund]?

    @Relationship(deleteRule: .nullify, inverse: \SinkingFundContribution.account)
    public var sinkingFundContributions: [SinkingFundContribution]?

    @Relationship(deleteRule: .nullify, inverse: \Goal.account)
    public var goals: [Goal]?

    public init(
        name: String,
        kind: AccountKind,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        colorHex: String = "#2F80ED",
        symbolName: String = "building.columns",
        institution: String = "",
        ownership: AccountOwnership = .personal,
        sortIndex: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.ownershipRaw = ownership.rawValue
        self.currencyCode = currencyCode
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.institution = institution
        self.sortIndex = sortIndex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .bank }
        set { kindRaw = newValue.rawValue }
    }

    public var ownership: AccountOwnership {
        get { AccountOwnership(rawValue: ownershipRaw) ?? .personal }
        set { ownershipRaw = newValue.rawValue }
    }

    public var isCompany: Bool {
        ownership == .company
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    public var balance: Money {
        Money(minorUnits: AccountBalance.balanceMinor(for: self), currency: currency)
    }

    public var displayName: String {
        name.isEmpty ? kind.displayName : name
    }
}
