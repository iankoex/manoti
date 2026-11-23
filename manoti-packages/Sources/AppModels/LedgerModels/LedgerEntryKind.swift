//
//  LedgerEntryKind.swift
//  AppModels
//

import Foundation

nonisolated public enum LedgerEntryKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case expense
    case income
    case openingBalance
    case adjustment
    case transferOut
    case transferIn
    case loanOut
    case loanIn
    case loanRepaymentOut
    case loanRepaymentIn
    case investmentOut
    case investmentIn
    case investmentIncome

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .expense: "Expense"
            case .income: "Income"
            case .openingBalance: "Opening balance"
            case .adjustment: "Adjustment"
            case .transferOut: "Transfer out"
            case .transferIn: "Transfer in"
            case .loanOut: "Loan given"
            case .loanIn: "Loan received"
            case .loanRepaymentOut: "Loan repayment"
            case .loanRepaymentIn: "Repayment received"
            case .investmentOut: "Investment purchase"
            case .investmentIn: "Investment redemption"
            case .investmentIncome: "Investment income"
        }
    }

    public var symbolName: String {
        switch self {
            case .expense: "arrow.up.right"
            case .income: "arrow.down.left"
            case .openingBalance: "flag"
            case .adjustment: "slider.horizontal.3"
            case .transferOut: "arrow.right"
            case .transferIn: "arrow.left"
            case .loanOut: "arrow.up.right"
            case .loanIn: "arrow.down.left"
            case .loanRepaymentOut: "arrow.up.right"
            case .loanRepaymentIn: "arrow.down.left"
            case .investmentOut: "chart.line.uptrend.xyaxis"
            case .investmentIn: "chart.line.downtrend.xyaxis"
            case .investmentIncome: "percent"
        }
    }

    public var isTransferLeg: Bool {
        self == .transferOut || self == .transferIn
    }

    public var countsAsSpending: Bool {
        self == .expense
    }

    public var countsAsIncome: Bool {
        self == .income || self == .investmentIncome
    }

    public var isInvestmentLeg: Bool {
        self == .investmentOut || self == .investmentIn || self == .investmentIncome
    }

    /// The category kind this entry should offer. Everything except income uses expenses.
    public var categoryKind: CategoryKind {
        self == .income ? .income : .expense
    }
}

nonisolated public enum LedgerEntryStatus: String, CaseIterable, Codable, Sendable {
    case confirmed
    case needsReview
    case ignored
}

nonisolated public enum LedgerEntrySource: String, CaseIterable, Codable, Sendable {
    case manual
    case message
    case shortcut
    case importRecord = "import"
    case reconcile
}

nonisolated public enum TransferStatus: String, CaseIterable, Codable, Sendable {
    case confirmed
    case needsReview
}
