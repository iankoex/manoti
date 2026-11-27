//
//  AccountOwnership.swift
//  AppModels
//

import Foundation

/// Whether an account holds the user's own money or a company's money.
///
/// Orthogonal to `AccountKind`: a company account is still a bank, mobile money, cash or card
/// account. Company accounts are excluded from personal spending reports and budgets.
nonisolated public enum AccountOwnership: String, CaseIterable, Codable, Sendable, Identifiable {
    case personal
    case company

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .personal: "Personal"
            case .company: "Company"
        }
    }
}

/// Which accounts a report should include.
nonisolated public enum AccountOwnershipScope: Sendable {
    case personal
    case all
}
