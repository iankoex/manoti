//
//  MovementRules.swift
//  AppServices
//

import AppModels
import Foundation

/// Pure rules for deciding whether two messages describe the same money movement.
///
/// The reference is the identity. Amount, direction and time are corroboration, so a
/// reversal or a receipt for a different amount is never folded into the original.
nonisolated enum MovementRules {
    /// A reference is unique, so the window is only a guard against a reused token.
    static let referenceWindow: TimeInterval = 48 * 60 * 60
    static let amountTolerance = 0.01

    static func normaliseReference(_ raw: String) -> String {
        raw
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// The references a message names: its own and the counterpart's, deduplicated.
    static func references(for message: ParsedMessage) -> [String] {
        var seen: Set<String> = []
        var refs: [String] = []

        for raw in [message.reference, message.counterpartReference] {
            let ref = normaliseReference(raw)
            guard !ref.isEmpty, seen.insert(ref).inserted else {
                continue
            }

            refs.append(ref)
        }

        return refs
    }

    /// Every reference an entry holds, including the receipt's.
    static func entryReferences(_ entry: LedgerEntry) -> [String] {
        [entry.externalRef, entry.counterpartRef, entry.confirmationRef]
            .map(normaliseReference)
            .filter { !$0.isEmpty }
    }

    static func referencesIntersect(entry: LedgerEntry, message: ParsedMessage) -> Bool {
        let messageRefs = Set(references(for: message))
        guard !messageRefs.isEmpty else {
            return false
        }

        return entryReferences(entry).contains { messageRefs.contains($0) }
    }

    /// True when the two amounts describe the same money.
    ///
    /// Base equality covers a payment and its receipt. One side's total (amount + fee)
    /// matching the other's base covers a transfer where one leg carries the fee.
    static func amountsAgree(
        minor: Int64,
        feeMinor: Int64,
        otherMinor: Int64,
        otherFeeMinor: Int64
    ) -> Bool {
        guard minor > 0, otherMinor > 0 else {
            return false
        }

        if minor == otherMinor {
            return true
        }

        let tolerance = max(1, Int64(Double(max(minor, otherMinor)) * amountTolerance))
        if abs((minor + feeMinor) - otherMinor) <= tolerance {
            return true
        }

        return abs((otherMinor + otherFeeMinor) - minor) <= tolerance
    }

    static func isWithinWindow(
        _ date: Date,
        _ other: Date,
        window: TimeInterval = referenceWindow
    ) -> Bool {
        abs(date.timeIntervalSince(other)) <= window
    }

    static func isOppositeTransferLeg(
        _ entry: LedgerEntry,
        messageType: LedgerEntryKind
    ) -> Bool {
        switch (entry.kind, messageType) {
            case (.transferOut, .transferIn), (.transferIn, .transferOut):
                return true
            default:
                return false
        }
    }

    /// A confirmation may only enrich a spending or income entry, never a transfer leg.
    /// A transaction matches the same kind, the opposite transfer leg, or a receipt-only
    /// entry awaiting its movement.
    static func directionCompatible(entry: LedgerEntry, message: ParsedMessage) -> Bool {
        if message.role == .confirmation {
            return entry.kind == .expense || entry.kind == .income
        }

        if isOppositeTransferLeg(entry, messageType: message.messageType) {
            return true
        }

        if entry.isConfirmationOnly {
            return true
        }

        switch (entry.kind, message.messageType) {
            case (.expense, .expense), (.income, .income):
                return true
            case (.transferOut, .transferOut), (.transferIn, .transferIn):
                return true
            default:
                return false
        }
    }
}
