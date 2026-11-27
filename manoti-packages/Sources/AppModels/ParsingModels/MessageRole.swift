//
//  MessageRole.swift
//  AppModels
//

import Foundation

/// What a message contributes to a money movement.
///
/// A transaction records money moving. A confirmation is a receipt for a movement another
/// message records: it can add detail, but it never creates a second entry once the movement
/// is known.
nonisolated public enum MessageRole: String, CaseIterable, Codable, Sendable {
    case transaction
    case confirmation

    public var displayName: String {
        switch self {
            case .transaction: "Transaction"
            case .confirmation: "Confirmation"
        }
    }
}
