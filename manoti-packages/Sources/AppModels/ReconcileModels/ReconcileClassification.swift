//
//  ReconcileClassification.swift
//  AppModels
//

import Foundation

/// Where one collected message sits after matching it against the ledger.
nonisolated public enum ReconcileClassification: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Collected but not yet matched; the state before `finalise`.
    case pending
    /// A strong one-to-one match with a posted ledger row.
    case matched
    /// A weak match the user must confirm before it counts.
    case possible
    /// A message the user has explicitly set aside.
    case ignored
    /// Parsed (or not) but absent from the ledger; offers Import.
    case missing
    /// The user imported this message into the ledger from the reconciliation screen.
    case imported

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .pending: "Pending"
            case .matched: "Matched"
            case .possible: "Possible"
            case .ignored: "Ignored"
            case .missing: "Missing from app"
            case .imported: "Imported"
        }
    }
}
