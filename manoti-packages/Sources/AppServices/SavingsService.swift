//
//  SavingsService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum SavingsError: Error, Equatable {
    case emptyName
    case invalidAmount
    case archivedAccount
    case currencyMismatch(expected: String, actual: String)
}

extension SavingsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .emptyName:
                return "Give this a name."
            case .invalidAmount:
                return "Enter an amount greater than zero."
            case .archivedAccount:
                return "That account is archived."
            case .currencyMismatch(let expected, let actual):
                return "This target is in \(actual). Choose an account in \(actual), not \(expected)."
        }
    }
}

/// Sinking funds and savings goals.
///
/// Contributions and goal progress are derived; nothing here changes account balances.
@Observable
public final class SavingsService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Sinking funds

    public func fetchFunds(includeArchived: Bool = false) throws -> [SinkingFund] {
        try context.fetch(
            FetchDescriptor<SinkingFund>(sortBy: [SortDescriptor(\SinkingFund.createdAt)])
        ).filter { includeArchived || !$0.isArchived }
    }

    @discardableResult
    public func createFund(
        name: String,
        targetMinor: Int64,
        monthlyAccrualMinor: Int64 = 0,
        targetDate: Date? = nil,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        category: SpendingCategory? = nil,
        account: Account? = nil,
        note: String = ""
    ) throws -> SinkingFund {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SavingsError.emptyName
        }

        guard targetMinor >= 0, monthlyAccrualMinor >= 0 else {
            throw SavingsError.invalidAmount
        }

        if let account, account.isArchived {
            throw SavingsError.archivedAccount
        }

        if let account, account.currencyCode != currencyCode {
            throw SavingsError.currencyMismatch(expected: account.currencyCode, actual: currencyCode)
        }

        let fund = SinkingFund(
            name: trimmed,
            targetMinor: targetMinor,
            currencyCode: currencyCode,
            monthlyAccrualMinor: monthlyAccrualMinor,
            targetDate: targetDate,
            category: category,
            account: account,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(fund)
        try save()
        return fund
    }

    public func updateFund(
        _ fund: SinkingFund,
        name: String,
        targetMinor: Int64,
        monthlyAccrualMinor: Int64,
        targetDate: Date?,
        currencyCode: String,
        category: SpendingCategory?,
        account: Account?,
        note: String,
        isArchived: Bool
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SavingsError.emptyName
        }

        guard targetMinor >= 0, monthlyAccrualMinor >= 0 else {
            throw SavingsError.invalidAmount
        }

        if let account, account.isArchived {
            throw SavingsError.archivedAccount
        }

        if let account, account.currencyCode != currencyCode {
            throw SavingsError.currencyMismatch(expected: account.currencyCode, actual: currencyCode)
        }

        fund.name = trimmed
        fund.targetMinor = targetMinor
        fund.currencyCode = currencyCode
        fund.monthlyAccrualMinor = monthlyAccrualMinor
        fund.targetDate = targetDate
        fund.category = category
        fund.account = account
        fund.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        fund.isArchived = isArchived
        try save()
    }

    public func contributions(for fund: SinkingFund) -> [SinkingFundContribution] {
        (fund.contributions ?? []).sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    @discardableResult
    public func addContribution(
        to fund: SinkingFund,
        amountMinor: Int64,
        occurredAt: Date = Date(),
        account: Account? = nil,
        note: String = ""
    ) throws -> SinkingFundContribution {
        guard amountMinor > 0 else {
            throw SavingsError.invalidAmount
        }

        if let account, account.isArchived {
            throw SavingsError.archivedAccount
        }

        let contribution = SinkingFundContribution(
            fund: fund,
            amountMinor: amountMinor,
            occurredAt: occurredAt,
            account: account,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(contribution)
        try save()
        return contribution
    }

    public func deleteContribution(_ contribution: SinkingFundContribution) throws {
        context.delete(contribution)
        try save()
    }

    // MARK: - Goals

    public func fetchGoals(includeArchived: Bool = false) throws -> [Goal] {
        try context.fetch(
            FetchDescriptor<Goal>(sortBy: [SortDescriptor(\Goal.createdAt)])
        ).filter { includeArchived || !$0.isArchived }
    }

    @discardableResult
    public func createGoal(
        name: String,
        targetMinor: Int64,
        targetDate: Date? = nil,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        account: Account? = nil,
        note: String = ""
    ) throws -> Goal {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SavingsError.emptyName
        }

        guard targetMinor >= 0 else {
            throw SavingsError.invalidAmount
        }

        if let account, account.isArchived {
            throw SavingsError.archivedAccount
        }

        if let account, account.currencyCode != currencyCode {
            throw SavingsError.currencyMismatch(expected: account.currencyCode, actual: currencyCode)
        }

        let goal = Goal(
            name: trimmed,
            targetMinor: targetMinor,
            currencyCode: currencyCode,
            targetDate: targetDate,
            account: account,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(goal)
        try save()
        return goal
    }

    public func updateGoal(
        _ goal: Goal,
        name: String,
        targetMinor: Int64,
        targetDate: Date?,
        currencyCode: String,
        account: Account?,
        note: String,
        isArchived: Bool
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SavingsError.emptyName
        }

        guard targetMinor >= 0 else {
            throw SavingsError.invalidAmount
        }

        if let account, account.isArchived {
            throw SavingsError.archivedAccount
        }

        if let account, account.currencyCode != currencyCode {
            throw SavingsError.currencyMismatch(expected: account.currencyCode, actual: currencyCode)
        }

        goal.name = trimmed
        goal.targetMinor = targetMinor
        goal.currencyCode = currencyCode
        goal.targetDate = targetDate
        goal.account = account
        goal.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.isArchived = isArchived
        try save()
    }

    private func save() throws {
        try context.save()
        ManotiNotifications.postDataChanged()
    }
}
