//
//  EntryFormType.swift
//  EntryFormFeature
//

import Foundation

/// What the user is recording, from the form's point of view.
///
/// A transfer is not a `LedgerEntryKind`: it is a `Transfer` with an out-leg and an in-leg.
/// The form uses this type so Review and Edit can offer the correction without pretending a
/// single kind is enough.
public enum EntryFormType: String, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case transfer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .expense: "Expense"
            case .income: "Income"
            case .transfer: "Transfer"
        }
    }
}
