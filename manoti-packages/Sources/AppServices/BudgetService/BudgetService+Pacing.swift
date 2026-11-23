//
//  BudgetService+Pacing.swift
//  AppServices
//

import AppModels
import Foundation

extension BudgetService {
    struct DayCounts: Equatable, Sendable {
        let totalDays: Int
        let elapsedDays: Int
        let daysRemaining: Int
    }

    /// Day counts for a start-inclusive, end-exclusive period.
    ///
    /// Day one counts as elapsed, so pacing never divides by zero on the first day. A period
    /// that has not started has no elapsed days; one that has ended has none remaining.
    func dayCounts(for period: BudgetPeriod, now: Date, calendar: Calendar) -> DayCounts {
        let totalDays = max(
            1,
            calendar.dateComponents([.day], from: period.startDate, to: period.endDate).day ?? 1
        )

        if now < period.startDate {
            return DayCounts(totalDays: totalDays, elapsedDays: 0, daysRemaining: totalDays)
        }

        if now >= period.endDate {
            return DayCounts(totalDays: totalDays, elapsedDays: totalDays, daysRemaining: 0)
        }

        let periodStart = calendar.startOfDay(for: period.startDate)
        let today = calendar.startOfDay(for: now)
        let dayIndex = calendar.dateComponents([.day], from: periodStart, to: today).day ?? 0
        let elapsed = min(totalDays, max(1, dayIndex + 1))
        let remaining = max(1, totalDays - elapsed + 1)

        return DayCounts(totalDays: totalDays, elapsedDays: elapsed, daysRemaining: remaining)
    }

    /// Straight-line projection of the period's spend, rounded to the nearest minor unit.
    ///
    /// Integer arithmetic keeps the result exact and avoids `Double`; a zero elapsed count
    /// projects zero rather than dividing.
    func projectedSpendMinor(spentMinor: Int64, totalDays: Int, elapsedDays: Int) -> Int64 {
        guard elapsedDays > 0, totalDays > 0, spentMinor != 0 else {
            return 0
        }

        let (product, overflow) = spentMinor.multipliedReportingOverflow(by: Int64(totalDays))
        guard !overflow else {
            return spentMinor
        }

        return (product + Int64(elapsedDays) / 2) / Int64(elapsedDays)
    }
}
