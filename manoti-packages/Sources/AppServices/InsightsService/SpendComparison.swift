//
//  SpendComparison.swift
//  AppServices
//

import AppModels
import Foundation

/// How one category's spending moved between the current and previous equal-elapsed windows.
nonisolated public struct CategorySpendDelta: Equatable, Sendable {
    public let categoryID: UUID
    public let name: String
    public let symbolName: String
    public let colorHex: String
    public let current: Money
    public let previous: Money
    public let difference: Money
    public let percentChange: Double?

    public init(
        categoryID: UUID,
        name: String,
        symbolName: String,
        colorHex: String,
        current: Money,
        previous: Money,
        difference: Money,
        percentChange: Double?
    ) {
        self.categoryID = categoryID
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.current = current
        self.previous = previous
        self.difference = difference
        self.percentChange = percentChange
    }
}

/// One day of the current window paired with the matching day of the previous window.
nonisolated public struct DailyComparisonPoint: Equatable, Sendable, Identifiable {
    /// One-based day within the window; day 1 is the first day of the period.
    public let dayIndex: Int
    public let currentDate: Date
    public let current: Money
    public let previous: Money

    public var id: Int { dayIndex }

    public init(dayIndex: Int, currentDate: Date, current: Money, previous: Money) {
        self.dayIndex = dayIndex
        self.currentDate = currentDate
        self.current = current
        self.previous = previous
    }
}

/// A payee and how often, and how much, they were paid in a window.
nonisolated public struct MerchantSpend: Equatable, Sendable, Identifiable {
    public let payee: String
    public let count: Int
    public let total: Money

    /// Payee names are grouped case-insensitively, so the name is a stable identifier here.
    public var id: String { payee }

    public init(payee: String, count: Int, total: Money) {
        self.payee = payee
        self.count = count
        self.total = total
    }
}

/// Small transactions in the current window, and the payees behind them.
nonisolated public struct SmallFrequentSpends: Equatable, Sendable {
    public let count: Int
    public let total: Money
    public let threshold: Money
    public let topPayees: [MerchantSpend]

    public init(count: Int, total: Money, threshold: Money, topPayees: [MerchantSpend]) {
        self.count = count
        self.total = total
        self.threshold = threshold
        self.topPayees = topPayees
    }
}

/// The difference between an account's computed ledger balance and the balance the bank last
/// reported. A non-zero difference almost always means a transaction is missing.
nonisolated public struct BalanceDrift: Equatable, Sendable, Identifiable {
    public let accountID: UUID
    public let name: String
    public let reportedBalance: Money
    public let ledgerBalance: Money
    public let difference: Money
    public let asOf: Date

    public var id: UUID { accountID }

    public init(
        accountID: UUID,
        name: String,
        reportedBalance: Money,
        ledgerBalance: Money,
        difference: Money,
        asOf: Date
    ) {
        self.accountID = accountID
        self.name = name
        self.reportedBalance = reportedBalance
        self.ledgerBalance = ledgerBalance
        self.difference = difference
        self.asOf = asOf
    }
}

/// Everything the Insights screen needs to compare the current period with the previous one
/// and with recent history, in one display currency.
///
/// Windows compare the same elapsed part of each period: on the 7th, the current month's
/// first seven days are compared with the previous month's first seven days (capped when the
/// previous month is shorter). The current window ends at the requested instant, so a mid-day
/// comparison includes today's entries so far. Only confirmed, non-ignored, non-deleted
/// expense rows count; transfer, loan and investment cash is excluded even when a row carries
/// the expense kind. Amounts are returned as-is; privacy masking and formatting belong to the
/// UI.
nonisolated public struct SpendComparison: Equatable, Sendable {
    public let kind: InsightPeriodKind
    public let currentInterval: DateInterval
    public let previousInterval: DateInterval
    public let elapsedDays: Int
    public let currentTotal: Money
    public let previousTotal: Money
    public let trailingAverage: Money?
    public let trailingSampleCount: Int
    public let percentChange: Double?
    public let fixedCurrent: Money
    public let fixedPrevious: Money
    public let variableCurrent: Money
    public let variablePrevious: Money
    public let categoryDeltas: [CategorySpendDelta]
    public let dailyPoints: [DailyComparisonPoint]
    public let topMerchants: [MerchantSpend]
    public let smallFrequent: SmallFrequentSpends?
    public let balanceDrift: [BalanceDrift]
    public let missingRates: [String]
    public let insufficientHistoryMessage: String?

    public init(
        kind: InsightPeriodKind,
        currentInterval: DateInterval,
        previousInterval: DateInterval,
        elapsedDays: Int,
        currentTotal: Money,
        previousTotal: Money,
        trailingAverage: Money?,
        trailingSampleCount: Int,
        percentChange: Double?,
        fixedCurrent: Money,
        fixedPrevious: Money,
        variableCurrent: Money,
        variablePrevious: Money,
        categoryDeltas: [CategorySpendDelta],
        dailyPoints: [DailyComparisonPoint],
        topMerchants: [MerchantSpend],
        smallFrequent: SmallFrequentSpends?,
        balanceDrift: [BalanceDrift],
        missingRates: [String],
        insufficientHistoryMessage: String?
    ) {
        self.kind = kind
        self.currentInterval = currentInterval
        self.previousInterval = previousInterval
        self.elapsedDays = elapsedDays
        self.currentTotal = currentTotal
        self.previousTotal = previousTotal
        self.trailingAverage = trailingAverage
        self.trailingSampleCount = trailingSampleCount
        self.percentChange = percentChange
        self.fixedCurrent = fixedCurrent
        self.fixedPrevious = fixedPrevious
        self.variableCurrent = variableCurrent
        self.variablePrevious = variablePrevious
        self.categoryDeltas = categoryDeltas
        self.dailyPoints = dailyPoints
        self.topMerchants = topMerchants
        self.smallFrequent = smallFrequent
        self.balanceDrift = balanceDrift
        self.missingRates = missingRates
        self.insufficientHistoryMessage = insufficientHistoryMessage
    }
}
