//
//  MovementCorrelator.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

/// Finds the entry a message belongs to.
///
/// Lookup is by reference only (`externalRef`, `counterpartRef`, `confirmationRef`); the
/// entry must then pass the amount, direction and time rules. A message with no reference
/// never matches, so a manual entry is never hijacked by a look-alike.
nonisolated struct MovementCorrelator {
    enum Match {
        /// The same movement. Either a duplicate delivery or a receipt waiting for its
        /// transaction.
        case entry(LedgerEntry)
        /// The opposite leg of a transfer.
        case counterpart(LedgerEntry)
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func match(for message: ParsedMessage) throws -> Match? {
        let refs = MovementRules.references(for: message)
        guard !refs.isEmpty else {
            return nil
        }

        let candidates = try entries(for: refs)
        let matching = candidates.filter { entry in
            guard !entry.isSoftDeleted,
                message.currencyCode.isEmpty || entry.currencyCode == message.currencyCode,
                MovementRules.directionCompatible(entry: entry, message: message),
                MovementRules.amountsAgree(
                    minor: message.amountMinor,
                    feeMinor: message.feeMinor,
                    otherMinor: entry.amountMinor,
                    otherFeeMinor: entry.feeMinor
                )
            else {
                return false
            }

            return MovementRules.isWithinWindow(message.occurredAt, entry.occurredAt)
        }

        guard !matching.isEmpty else {
            return nil
        }

        let primary = MovementRules.normaliseReference(message.reference)
        let sorted = matching.sorted { lhs, rhs in
            // The entry that owns this message's own reference beats one that only names it
            // as a counterpart. This keeps a repeated M-PESA receipt on its own in-leg
            // instead of re-pairing it with the transfer's out-leg.
            let lhsPrimary =
                !primary.isEmpty && MovementRules.normaliseReference(lhs.externalRef) == primary
            let rhsPrimary =
                !primary.isEmpty && MovementRules.normaliseReference(rhs.externalRef) == primary

            if lhsPrimary != rhsPrimary {
                return lhsPrimary
            }

            let lhsOpposite = MovementRules.isOppositeTransferLeg(lhs, messageType: message.messageType)
            let rhsOpposite = MovementRules.isOppositeTransferLeg(rhs, messageType: message.messageType)

            if lhsOpposite != rhsOpposite {
                return lhsOpposite
            }

            let lhsGap = abs(lhs.occurredAt.timeIntervalSince(message.occurredAt))
            let rhsGap = abs(rhs.occurredAt.timeIntervalSince(message.occurredAt))
            if lhsGap != rhsGap {
                return lhsGap < rhsGap
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }

        let best = sorted[0]
        if MovementRules.isOppositeTransferLeg(best, messageType: message.messageType) {
            return .counterpart(best)
        }

        return .entry(best)
    }

    /// Entries whose stored reference equals any reference the message names.
    ///
    /// Three small fetches per reference keep this safe with SwiftData's predicate macro,
    /// which cannot map over a key-path array.
    private func entries(for refs: [String]) throws -> [LedgerEntry] {
        var found: [UUID: LedgerEntry] = [:]

        for ref in refs {
            // Soft-deleted entries are included on purpose: a deleted movement should absorb
            // a late message instead of being resurrected as a new row. Callers decide.
            let byExternal = FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> { $0.externalRef == ref }
            )
            let byCounterpart = FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> { $0.counterpartRef == ref }
            )
            let byConfirmation = FetchDescriptor<LedgerEntry>(
                predicate: #Predicate<LedgerEntry> { $0.confirmationRef == ref }
            )

            let external = try context.fetch(byExternal)
            let counterpart = try context.fetch(byCounterpart)
            let confirmation = try context.fetch(byConfirmation)

            for entry in external + counterpart + confirmation {
                found[entry.id] = entry
            }
        }

        return Array(found.values)
    }
}
