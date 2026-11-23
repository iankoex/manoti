//
//  BudgetPeriod.swift
//  AppModels
//

import Foundation
import SwiftData

/// One month or week that envelopes belong to.
///
/// The service creates the period on demand and never duplicates it, so a period is the
/// stable anchor for envelope limits and rolled-over balances.
@Model
public final class BudgetPeriod {
    public var id: UUID = UUID()
    public var kindRaw: String = BudgetPeriodKind.month.rawValue

    /// Start of the period, inclusive.
    public var startDate: Date = Date()

    /// End of the period, exclusive.
    public var endDate: Date = Date()
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Envelope.period)
    public var envelopes: [Envelope]?

    public init(kind: BudgetPeriodKind, startDate: Date, endDate: Date) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = Date()
    }

    public convenience init(kind: BudgetPeriodKind, containing date: Date, calendar: Calendar) {
        let interval = kind.dateInterval(containing: date, calendar: calendar)
        self.init(kind: kind, startDate: interval.start, endDate: interval.end)
    }

    public var kind: BudgetPeriodKind {
        get { BudgetPeriodKind(rawValue: kindRaw) ?? .month }
        set { kindRaw = newValue.rawValue }
    }

    public var interval: DateInterval {
        DateInterval(start: startDate, end: max(startDate, endDate))
    }
}
