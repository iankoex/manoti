//
//  LoanFormState.swift
//  LoansFeature
//

import AppModels
import AppServices
import Foundation
import Observation

public enum LoanFormError: Error, Equatable {
    case missingAccount
    case invalidAmount
}

/// Editable state for creating a loan.
///
/// Validation mirrors `LoanService.create` so the Save button stays disabled until the
/// service would accept the input.
@MainActor
@Observable
public final class LoanFormState {
    public var direction: LoanDirection
    public var counterparty = ""
    public var amountText = ""
    public var selectedAccountID: UUID?
    public var startedAt = Date.now
    public var dueAt: Date?
    public var note = ""

    public var accounts: [Account] = []

    public init(direction: LoanDirection = .lent) {
        self.direction = direction
    }

    public var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    public var selectedAccount: Account? {
        guard let selectedAccountID else {
            return activeAccounts.first
        }

        return activeAccounts.first { $0.id == selectedAccountID }
    }

    public var trimmedCounterparty: String {
        counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var parsedAmount: Money? {
        guard let selectedAccount else {
            return nil
        }

        return MoneyParser.parse(amountText, defaultCurrency: selectedAccount.currency)?.money
    }

    public var canSave: Bool {
        guard let selectedAccount, !trimmedCounterparty.isEmpty else {
            return false
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: selectedAccount.currency) else {
            return false
        }

        return parsed.money.minorUnits > 0
    }

    public func reload(accountService: AccountService) {
        accounts = (try? accountService.fetchAccounts(includeArchived: true)) ?? []
        selectDefaultAccount()
    }

    public func selectDefaultAccount() {
        if let selectedAccountID, activeAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        selectedAccountID = activeAccounts.first?.id
    }

    @discardableResult
    public func save(loanService: LoanService) throws -> Loan {
        guard let account = selectedAccount else {
            throw LoanFormError.missingAccount
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: account.currency),
            parsed.money.minorUnits > 0
        else {
            throw LoanFormError.invalidAmount
        }

        return try loanService.create(
            direction: direction,
            counterparty: counterparty,
            principalMinor: parsed.money.minorUnits,
            account: account,
            startedAt: startedAt,
            dueAt: dueAt,
            note: note
        )
    }
}
