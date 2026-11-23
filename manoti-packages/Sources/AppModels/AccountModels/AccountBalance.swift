//
//  AccountBalance.swift
//  AppModels
//

import Foundation

/// Balance is always the sum of ledger entries. There is no separate opening-balance field,
/// so an account's balance can never be counted twice.
nonisolated public enum AccountBalance {
    public static func balanceMinor(for account: Account) -> Int64 {
        (account.transactions ?? [])
            .filter(\.isPosted)
            .reduce(into: Int64(0)) { total, transaction in
                total += transaction.signedAmountMinor
            }
    }

    public static func balance(for account: Account) -> Money {
        Money(minorUnits: balanceMinor(for: account), currency: account.currency)
    }
}
