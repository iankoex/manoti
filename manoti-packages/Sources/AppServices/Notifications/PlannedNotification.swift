//
//  PlannedNotification.swift
//  AppServices
//

import Foundation

/// A notification the planner wants scheduled. Stable identifiers let a refresh replace a
/// previous request rather than stack duplicates.
nonisolated public struct PlannedNotification: Sendable, Equatable, Identifiable {
    nonisolated public enum Kind: String, CaseIterable, Sendable, Equatable {
        case dailyReminder
        case inboxReminder
        case weeklySummary
        case budgetWarning
        case budgetOver
        case largeTransaction
    }

    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date
    public let kind: Kind

    /// Present on budget alerts so the service can record the period that fired.
    public let budgetEnvelopeID: UUID?
    public let budgetThresholdPercent: Int?
    public let budgetPeriodStart: Date?

    public var id: String { identifier }

    public init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        kind: Kind,
        budgetEnvelopeID: UUID? = nil,
        budgetThresholdPercent: Int? = nil,
        budgetPeriodStart: Date? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.kind = kind
        self.budgetEnvelopeID = budgetEnvelopeID
        self.budgetThresholdPercent = budgetThresholdPercent
        self.budgetPeriodStart = budgetPeriodStart
    }
}
