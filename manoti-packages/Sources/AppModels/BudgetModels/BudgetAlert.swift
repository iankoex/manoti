//
//  BudgetAlert.swift
//  AppModels
//

import Foundation
import SwiftData

/// A threshold an envelope has crossed, recorded once per period so the in-app alert can
/// fire exactly once and later be reused by local notifications.
@Model
public final class BudgetAlert {
    /// The thresholds the dashboard surfaces.
    public static let thresholds: [Int] = [80, 100]

    public var id: UUID = UUID()
    public var thresholdPercent: Int = 80
    public var lastTriggeredPeriodStart: Date?
    public var createdAt: Date = Date()

    public var envelope: Envelope?

    public init(envelope: Envelope? = nil, thresholdPercent: Int = 80, lastTriggeredPeriodStart: Date? = nil) {
        self.id = UUID()
        self.envelope = envelope
        self.thresholdPercent = thresholdPercent
        self.lastTriggeredPeriodStart = lastTriggeredPeriodStart
        self.createdAt = Date()
    }
}
