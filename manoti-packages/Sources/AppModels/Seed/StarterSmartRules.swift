//
//  StarterSmartRules.swift
//  AppModels
//

import Foundation

nonisolated public struct SeedSmartRule: Sendable {
    public let name: String
    public let seedKey: String
    public let priority: Int
    public let conditions: SmartRuleConditions
    public let targetCategoryName: String
    public let confidenceBoost: Double

    public init(
        name: String,
        seedKey: String,
        priority: Int,
        conditions: SmartRuleConditions,
        targetCategoryName: String,
        confidenceBoost: Double = 0
    ) {
        self.name = name
        self.seedKey = seedKey
        self.priority = priority
        self.conditions = conditions
        self.targetCategoryName = targetCategoryName
        self.confidenceBoost = confidenceBoost
    }
}

public enum StarterSmartRules {
    private static let weekdays = [2, 3, 4, 5, 6]

    public static let rules: [SeedSmartRule] = [
        SeedSmartRule(
            name: "Morning commute",
            seedKey: "morning-commute",
            priority: 0,
            conditions: SmartRuleConditions(
                amountMaxMinor: 10_000,
                timeStartMinutes: 7 * 60,
                timeEndMinutes: 9 * 60,
                weekdays: weekdays
            ),
            targetCategoryName: "Bus/Matatu",
            confidenceBoost: 0.1
        ),
        SeedSmartRule(
            name: "Lunch",
            seedKey: "lunch",
            priority: 1,
            conditions: SmartRuleConditions(
                amountMinMinor: 15_000,
                amountMaxMinor: 35_000,
                timeStartMinutes: 12 * 60,
                timeEndMinutes: 14 * 60 + 30,
                weekdays: weekdays
            ),
            targetCategoryName: "Lunch",
            confidenceBoost: 0.1
        ),
        SeedSmartRule(
            name: "Evening commute",
            seedKey: "evening-commute",
            priority: 2,
            conditions: SmartRuleConditions(
                amountMaxMinor: 15_000,
                timeStartMinutes: 17 * 60,
                timeEndMinutes: 19 * 60 + 30,
                weekdays: weekdays
            ),
            targetCategoryName: "Bus/Matatu",
            confidenceBoost: 0
        ),
        SeedSmartRule(
            name: "Supermarket",
            seedKey: "supermarket",
            priority: 3,
            conditions: SmartRuleConditions(
                amountMinMinor: 50_000,
                payeeContains: ["market", "mart", "supermarket", "naivas", "quickmart", "carrefour"]
            ),
            targetCategoryName: "Groceries",
            confidenceBoost: 0.2
        ),
        SeedSmartRule(
            name: "Fuel",
            seedKey: "fuel",
            priority: 4,
            conditions: SmartRuleConditions(
                payeeContains: ["shell", "total", "kobil", "topline", "petrol", "fuel"]
            ),
            targetCategoryName: "Fuel",
            confidenceBoost: 0.2
        ),
        SeedSmartRule(
            name: "Uber ride",
            seedKey: "ride-uber",
            priority: 5,
            conditions: SmartRuleConditions(contextMerchant: "uber"),
            targetCategoryName: "Ride-hailing",
            confidenceBoost: 0.25
        ),
        SeedSmartRule(
            name: "Bolt ride",
            seedKey: "ride-bolt",
            priority: 6,
            conditions: SmartRuleConditions(contextMerchant: "bolt"),
            targetCategoryName: "Ride-hailing",
            confidenceBoost: 0.25
        ),
    ]
}
