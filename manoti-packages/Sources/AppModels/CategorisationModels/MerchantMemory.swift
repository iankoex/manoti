//
//  MerchantMemory.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class MerchantMemory {
    public var id: UUID = UUID()
    public var merchantKey: String = ""
    public var displayName: String = ""
    public var category: SpendingCategory?
    public var account: Account?
    public var timesSeen: Int = 0
    public var lastSeenAt: Date = Date()
    public var autoApply: Bool = false
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \MerchantAlias.merchantMemory)
    public var aliases: [MerchantAlias]?

    public init(merchantKey: String, displayName: String) {
        self.id = UUID()
        self.merchantKey = merchantKey
        self.displayName = displayName
    }
}

@Model
public final class MerchantAlias {
    public var id: UUID = UUID()
    public var aliasKey: String = ""
    public var merchantMemory: MerchantMemory?

    public init(aliasKey: String) {
        self.id = UUID()
        self.aliasKey = aliasKey
    }
}
