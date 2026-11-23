//
//  InsightPeriodKind.swift
//  AppServices
//

import Foundation

/// A calendar period Insights can compare: a month or a week.
///
/// Weeks follow `Calendar.firstWeekday`; callers should apply
/// `AppSettings.weekStartsOn` to the calendar before asking for a comparison.
nonisolated public enum InsightPeriodKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case month
    case week

    public var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
            case .month: .month
            case .week: .weekOfYear
        }
    }
}
