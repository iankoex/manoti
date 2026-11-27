//
//  LedgerEntryPresentation.swift
//  LedgerFeature
//

import AppModels
import Modifiers
import SwiftUI

/// Shared presentation rules for a ledger row and its detail screen.
enum LedgerEntryPresentation {
    static func title(for entry: LedgerEntry) -> String {
        if let loan = entry.loan {
            switch entry.kind {
                case .loanOut: return "Loan to \(loan.counterparty)"
                case .loanIn: return "Loan from \(loan.counterparty)"
                case .loanRepaymentIn: return "Repayment from \(loan.counterparty)"
                case .loanRepaymentOut: return "Repayment to \(loan.counterparty)"
                default: break
            }
        }

        if !entry.payee.isEmpty {
            return entry.payee
        }

        if let category = entry.primaryCategory {
            return category.name
        }

        return entry.kind.displayName
    }

    static func symbolName(for entry: LedgerEntry) -> String {
        entry.primaryCategory?.symbolName ?? entry.kind.symbolName
    }

    static func tint(for entry: LedgerEntry) -> Color {
        ManotiColor.forHex(entry.primaryCategory?.colorHex ?? "#8E8E93")
    }

    static func sourceName(for source: LedgerEntrySource) -> String {
        switch source {
            case .manual: return "Manual"
            case .message: return "Message"
            case .shortcut: return "Shortcut"
            case .importRecord: return "Import"
            case .reconcile: return "Reconciliation"
        }
    }
}
