//
//  LoanBalance.swift
//  AppModels
//

import Foundation

/// Outstanding is the principal minus the repayments that still post.
///
/// A fee on a repayment is a cost of moving the money, not principal, so only `amountMinor`
/// reduces the balance.
nonisolated public enum LoanBalance {
    public static func outstandingMinor(for loan: Loan) -> Int64 {
        let repaymentKind: LedgerEntryKind = loan.direction == .lent ? .loanRepaymentIn : .loanRepaymentOut
        let repaid = (loan.entries ?? [])
            .filter { $0.kind == repaymentKind && !$0.isSoftDeleted }
            .reduce(into: Int64(0)) { total, entry in
                total += entry.amountMinor
            }

        return max(0, loan.principalMinor - repaid)
    }
}
