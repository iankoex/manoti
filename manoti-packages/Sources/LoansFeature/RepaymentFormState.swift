//
//  RepaymentFormState.swift
//  LoansFeature
//

import AppModels
import AppServices
import Foundation
import Observation

/// Editable state for recording a repayment against an open loan.
///
/// The form rejects overpayments before saving, and `LoanService` remains the final
/// authority if the outstanding balance changes while the sheet is open.
@MainActor
@Observable
public final class RepaymentFormState {
    public let loan: Loan
    public var amountText = ""
    public var selectedAccountID: UUID?
    public var occurredAt = Date.now
    public var note = ""

    public var accounts: [Account] = []

    public init(loan: Loan) {
        self.loan = loan
    }

    public var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    public var selectedAccount: Account? {
        guard let selectedAccountID else {
            return eligibleAccounts.first
        }

        return eligibleAccounts.first { $0.id == selectedAccountID }
    }

    public var eligibleAccounts: [Account] {
        activeAccounts.filter { $0.currency == loan.currency }
    }

    public var outstanding: Money {
        loan.outstanding
    }

    public var parsedAmount: Money? {
        guard let selectedAccount else {
            return nil
        }

        return MoneyParser.parse(amountText, defaultCurrency: selectedAccount.currency)?.money
    }

    public var remainingPreview: Money? {
        guard let parsed = parsedAmount, parsed.minorUnits > 0 else {
            return nil
        }

        return Money(
            minorUnits: max(0, loan.outstandingMinor - parsed.minorUnits),
            currency: loan.currency
        )
    }

    public var canSave: Bool {
        guard loan.outstandingMinor > 0, loan.status == .open else {
            return false
        }

        guard let account = selectedAccount, account.currency == loan.currency else {
            return false
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: account.currency) else {
            return false
        }

        return parsed.money.minorUnits > 0 && parsed.money.minorUnits <= loan.outstandingMinor
    }

    /// The first blocking problem, phrased for an inline red footer.
    public var validationMessage: String? {
        guard loan.outstandingMinor > 0, loan.status == .open else {
            return "This loan is already settled."
        }

        guard let account = selectedAccount else {
            return activeAccounts.isEmpty
                ? "Choose an account for the repayment."
                : "Add a \(loan.currency.code) account for this loan."
        }

        guard account.currency == loan.currency else {
            return "Use a \(loan.currency.code) account for this loan."
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: account.currency) else {
            return nil
        }

        guard parsed.money.minorUnits > 0 else {
            return nil
        }

        guard parsed.money.minorUnits <= loan.outstandingMinor else {
            return "Repayment cannot exceed the outstanding amount."
        }

        return nil
    }

    public func reload(accountService: AccountService) {
        accounts = (try? accountService.fetchAccounts(includeArchived: true)) ?? []
        selectDefaultAccount()
    }

    public func selectDefaultAccount() {
        if let selectedAccountID, eligibleAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        selectedAccountID = eligibleAccounts.first?.id
    }

    @discardableResult
    public func save(loanService: LoanService) throws -> LedgerEntry {
        guard let account = selectedAccount else {
            throw LoanFormError.missingAccount
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: account.currency),
            parsed.money.minorUnits > 0
        else {
            throw LoanFormError.invalidAmount
        }

        return try loanService.addRepayment(
            to: loan,
            amountMinor: parsed.money.minorUnits,
            account: account,
            occurredAt: occurredAt,
            note: note
        )
    }
}
