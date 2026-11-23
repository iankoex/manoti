//
//  LoanService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum LoanError: Error, Equatable {
    case invalidAmount
    case invalidCounterparty
    case archivedAccount
    case currencyMismatch
    case overpayment
}

/// Creates loans, records repayments and soft-deletes mistakes.
///
/// Every cash movement is an ordinary `LedgerEntry`, so account balances stay the single
/// source of truth.
@Observable
public final class LoanService: Loggable {
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func fetchLoans(includeSettled: Bool = true) throws -> [Loan] {
        var descriptor = FetchDescriptor<Loan>(
            sortBy: [
                SortDescriptor(\Loan.startedAt, order: .reverse),
                SortDescriptor(\Loan.createdAt, order: .reverse),
            ]
        )

        if includeSettled {
            descriptor.predicate = #Predicate<Loan> { !$0.isSoftDeleted }
        } else {
            descriptor.predicate = #Predicate<Loan> { !$0.isSoftDeleted && $0.statusRaw == "open" }
        }

        return try context.fetch(descriptor)
    }

    @discardableResult
    public func create(
        direction: LoanDirection,
        counterparty: String,
        principalMinor: Int64,
        account: Account,
        startedAt: Date = Date(),
        dueAt: Date? = nil,
        note: String = ""
    ) throws -> Loan {
        guard principalMinor > 0 else {
            throw LoanError.invalidAmount
        }

        let trimmedCounterparty = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCounterparty.isEmpty else {
            throw LoanError.invalidCounterparty
        }

        guard !account.isArchived else {
            throw LoanError.archivedAccount
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let loan = Loan(
            direction: direction,
            counterparty: trimmedCounterparty,
            principalMinor: principalMinor,
            currencyCode: account.currencyCode,
            startedAt: startedAt,
            dueAt: dueAt,
            note: trimmedNote
        )
        context.insert(loan)

        let entry = LedgerEntry(
            kind: direction == .lent ? .loanOut : .loanIn,
            amountMinor: principalMinor,
            currencyCode: account.currencyCode,
            occurredAt: startedAt,
            payee: trimmedCounterparty,
            note: trimmedNote
        )
        entry.account = account
        entry.loan = loan
        context.insert(entry)

        try context.save()
        ManotiNotifications.postDataChanged()
        log("Created \(direction.rawValue) loan for \(trimmedCounterparty)", level: .info)
        return loan
    }

    @discardableResult
    public func addRepayment(
        to loan: Loan,
        amountMinor: Int64,
        account: Account,
        occurredAt: Date = Date(),
        note: String = ""
    ) throws -> LedgerEntry {
        guard amountMinor > 0 else {
            throw LoanError.invalidAmount
        }

        guard !account.isArchived else {
            throw LoanError.archivedAccount
        }

        guard account.currency == loan.currency else {
            throw LoanError.currencyMismatch
        }

        let outstanding = loan.outstandingMinor
        guard amountMinor <= outstanding else {
            throw LoanError.overpayment
        }

        let remaining = outstanding - amountMinor
        let entry = LedgerEntry(
            kind: loan.direction == .lent ? .loanRepaymentIn : .loanRepaymentOut,
            amountMinor: amountMinor,
            currencyCode: account.currencyCode,
            occurredAt: occurredAt,
            payee: loan.counterparty,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        entry.account = account
        entry.loan = loan
        context.insert(entry)

        loan.updatedAt = Date()
        if remaining == 0 {
            loan.status = .settled
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        log("Recorded repayment of \(amountMinor) \(loan.currencyCode) for \(loan.counterparty)", level: .info)
        return entry
    }

    /// Soft-deletes the loan and every linked entry, so the account balance reverses and the
    /// rows can still be recovered by a future undo.
    public func delete(_ loan: Loan) throws {
        guard !loan.isSoftDeleted else {
            return
        }

        loan.isSoftDeleted = true
        loan.updatedAt = Date()

        for entry in loan.entries ?? [] where !entry.isSoftDeleted {
            entry.isSoftDeleted = true
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        log("Deleted loan for \(loan.counterparty)", level: .info)
    }
}
