//
//  CategoryKind.swift
//  AppModels
//

import Foundation

/// Whether a category describes money going out or money coming in.
///
/// The Add sheet, budget envelopes and Inbox suggestions filter on this, so an expense
/// never offers "Salary" and income never offers "Lunch".
nonisolated public enum CategoryKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case expense
    case income

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .expense: "Expense"
            case .income: "Income"
        }
    }
}
