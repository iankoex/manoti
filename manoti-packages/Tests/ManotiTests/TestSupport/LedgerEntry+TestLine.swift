//
//  LedgerEntry+TestLine.swift
//  ManotiTests
//

import AppModels
import SwiftData

extension LedgerEntry {
    /// Test-only shorthand for the single line the app writes for an expense or income.
    func attachSingleLine(
        amountMinor: Int64? = nil,
        category: SpendingCategory?,
        in context: ModelContext
    ) {
        guard kind == .expense || kind == .income else {
            return
        }

        let line = LedgerEntryLine(amountMinor: amountMinor ?? self.amountMinor, category: category)
        context.insert(line)
        line.entry = self
        lines = [line]
    }
}
