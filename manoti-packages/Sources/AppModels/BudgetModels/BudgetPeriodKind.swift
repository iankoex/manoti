//
//  BudgetPeriodKind.swift
//  AppModels
//

import Foundation

/// How a budget period is bounded: a calendar month or a calendar week.
nonisolated public enum BudgetPeriodKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case month
    case week

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .month: "Month"
            case .week: "Week"
        }
    }

    /// The start-inclusive, end-exclusive interval containing `date`.
    ///
    /// Weeks follow `calendar.firstWeekday`, so callers should apply
    /// `AppSettings.weekStartsOn` to the calendar before asking for a period.
    public func dateInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component = self == .month ? .month : .weekOfYear

        if let interval = calendar.dateInterval(of: component, for: date) {
            return interval
        }

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}
