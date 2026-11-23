//
//  NotificationBudgetRow.swift
//  AppServices
//

import Foundation

/// One envelope's current-period position, already converted to the display currency.
nonisolated public struct NotificationBudgetRow: Sendable, Equatable, Identifiable {
    public var envelopeID: UUID
    public var categoryName: String
    public var spentMinor: Int64
    public var limitMinor: Int64
    public var periodStart: Date
    /// The highest threshold already notified for this period, or zero when none has fired.
    public var lastAlertPercent: Int

    public var id: UUID { envelopeID }

    public init(
        envelopeID: UUID,
        categoryName: String,
        spentMinor: Int64,
        limitMinor: Int64,
        periodStart: Date,
        lastAlertPercent: Int = 0
    ) {
        self.envelopeID = envelopeID
        self.categoryName = categoryName
        self.spentMinor = spentMinor
        self.limitMinor = limitMinor
        self.periodStart = periodStart
        self.lastAlertPercent = lastAlertPercent
    }
}
