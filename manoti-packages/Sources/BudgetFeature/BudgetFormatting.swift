//
//  BudgetFormatting.swift
//  BudgetFeature
//

import AppModels
import Foundation

/// Small, testable formatting helpers shared by the budget cards and rows.
enum BudgetFormatting {
    /// Progress from zero to one, clamped so an overspent envelope never overdraws its bar.
    static func progressFraction(spentMinor: Int64, limitMinor: Int64) -> Double {
        guard limitMinor > 0, spentMinor > 0 else {
            return 0
        }

        return min(1, Double(spentMinor) / Double(limitMinor))
    }

    /// How much of the limit has been used, as a whole percentage.
    ///
    /// Returns `nil` for an envelope without a limit, and keeps values above 100 so an
    /// overspent row can say so.
    static func percentUsed(spentMinor: Int64, limitMinor: Int64) -> Int? {
        guard limitMinor > 0 else {
            return nil
        }

        let percentage = (Double(spentMinor) / Double(limitMinor) * 100).rounded()
        return Int(percentage)
    }

    /// Elapsed share of the period, clamped to the bar.
    static func pacingFraction(totalDays: Int, elapsedDays: Int) -> Double {
        guard totalDays > 0, elapsedDays > 0 else {
            return 0
        }

        return min(1, Double(elapsedDays) / Double(totalDays))
    }

    /// Title for the period switcher, using calendar dates rather than fixed day counts.
    static func periodTitle(kind: BudgetPeriodKind, startDate: Date, calendar: Calendar) -> String {
        switch kind {
            case .month:
                return startDate.formatted(.dateTime.month(.wide).year())
            case .week:
                guard
                    let lastDay = calendar.date(
                        byAdding: .day, value: -1, to: endDate(after: startDate, calendar: calendar))
                else {
                    return startDate.formatted(date: .abbreviated, time: .omitted)
                }

                let start = startDate.formatted(date: .abbreviated, time: .omitted)
                let end = lastDay.formatted(date: .abbreviated, time: .omitted)
                return "\(start) – \(end)"
        }
    }

    /// The Plan card's envelope count, with a singular form.
    static func envelopeCount(_ count: Int, kind: BudgetPeriodKind) -> String {
        let noun = count == 1 ? "envelope" : "envelopes"
        return "\(count) \(noun) · \(kind.displayName.lowercased())"
    }

    /// Plain editable text for a limit, with no grouping or currency token.
    static func limitText(for money: Money) -> String {
        NSDecimalNumber(decimal: money.decimalValue).stringValue
    }

    private static func endDate(after startDate: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .weekOfYear, value: 1, to: startDate) ?? startDate
    }
}
