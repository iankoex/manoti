//
//  SmartRule.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class SmartRule {
    public var id: UUID = UUID()
    public var name: String = ""
    public var seedKey: String = ""
    public var isEnabled: Bool = true
    public var priority: Int = 0
    public var conditionsJSON: String = "{}"
    public var targetCategory: SpendingCategory?
    public var confidenceBoost: Double = 0
    public var timesApplied: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        name: String,
        seedKey: String = "",
        priority: Int,
        conditions: SmartRuleConditions,
        confidenceBoost: Double = 0
    ) {
        self.id = UUID()
        self.name = name
        self.seedKey = seedKey
        self.priority = priority
        self.conditions = conditions
        self.confidenceBoost = confidenceBoost
    }

    public var conditions: SmartRuleConditions {
        get {
            guard let data = conditionsJSON.data(using: .utf8),
                let decoded = try? JSONDecoder().decode(SmartRuleConditions.self, from: data)
            else {
                return SmartRuleConditions()
            }

            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                let text = String(data: data, encoding: .utf8)
            else {
                return
            }

            conditionsJSON = text
        }
    }
}

@Model
public final class ContextWindow {
    public var id: UUID = UUID()
    public var merchant: String = ""
    public var startedAt: Date = Date()
    public var expiresAt: Date = Date()
    public var sourceApp: String = ""

    public init(merchant: String, startedAt: Date = Date(), expiresAt: Date, sourceApp: String = "") {
        self.id = UUID()
        self.merchant = merchant
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.sourceApp = sourceApp
    }

    public func isActive(at date: Date = Date()) -> Bool {
        date >= startedAt && date <= expiresAt
    }
}
