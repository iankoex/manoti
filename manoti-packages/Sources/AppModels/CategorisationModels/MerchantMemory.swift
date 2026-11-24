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

    /// Per-category tally, JSON-encoded so the store migrates lightly. A merchant that
    /// is filed under two categories keeps both counts; `category` stays the last
    /// explicit choice.
    public var categoryCountsJSON: String = ""

    @Relationship(deleteRule: .cascade, inverse: \MerchantAlias.merchantMemory)
    public var aliases: [MerchantAlias]?

    public init(merchantKey: String, displayName: String) {
        self.id = UUID()
        self.merchantKey = merchantKey
        self.displayName = displayName
    }

    public var categoryCounts: [UUID: Int] {
        get {
            guard let data = categoryCountsJSON.data(using: .utf8),
                let raw = try? JSONDecoder().decode([String: Int].self, from: data)
            else {
                return [:]
            }

            return raw.reduce(into: [:]) { counts, pair in
                guard let id = UUID(uuidString: pair.key) else {
                    return
                }

                counts[id] = pair.value
            }
        }
        set {
            let raw = newValue.reduce(into: [String: Int]()) { result, pair in
                result[pair.key.uuidString] = pair.value
            }

            guard let data = try? JSONEncoder().encode(raw),
                let json = String(data: data, encoding: .utf8)
            else {
                return
            }

            categoryCountsJSON = json
        }
    }

    /// Records one filing under a category and returns that category's new count.
    @discardableResult
    public func record(categoryID: UUID) -> Int {
        var counts = categoryCounts
        counts[categoryID, default: 0] += 1
        categoryCounts = counts
        return counts[categoryID] ?? 0
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
