//
//  TransferLinker.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

/// Links two existing ledger legs into one transfer.
///
/// Kept outside `TransferService` so a nonisolated caller such as `IngestService` can link
/// the two legs a pair of bank messages produced without hopping to the main actor.
nonisolated struct TransferLinker {
    static let matchWindow: TimeInterval = 15 * 60

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func link(outLeg: LedgerEntry, inLeg: LedgerEntry) throws -> Transfer {
        guard outLeg.kind == .transferOut, inLeg.kind == .transferIn else {
            throw TransferError.wrongLegKinds
        }

        guard outLeg.transfer == nil, inLeg.transfer == nil else {
            throw TransferError.alreadyLinked
        }

        guard let from = outLeg.account, let to = inLeg.account, from.id != to.id else {
            throw TransferError.sameAccount
        }

        guard outLeg.isPosted, inLeg.isPosted, !from.isArchived, !to.isArchived else {
            throw TransferError.archivedAccount
        }

        // A shared reference is strong enough to survive any delay. Without one, two legs
        // this far apart are more likely a repeated transfer than the same movement.
        if !referenceMatches(outLeg: outLeg, inLeg: inLeg),
            abs(outLeg.occurredAt.timeIntervalSince(inLeg.occurredAt)) > Self.matchWindow
        {
            throw TransferError.timeMismatch
        }

        let occurredAt = min(outLeg.occurredAt, inLeg.occurredAt)
        let transfer = Transfer(occurredAt: occurredAt)
        transfer.fromAccount = from
        transfer.toAccount = to
        context.insert(transfer)

        outLeg.transfer = transfer
        inLeg.transfer = transfer

        if from.currency != to.currency {
            recordRate(
                from: from,
                to: to,
                amountOutMinor: outLeg.amountMinor,
                amountInMinor: inLeg.amountMinor,
                at: occurredAt
            )
        }

        try context.save()
        return transfer
    }

    private func referenceMatches(outLeg: LedgerEntry, inLeg: LedgerEntry) -> Bool {
        guard outLeg.kind == .transferOut, inLeg.kind == .transferIn else {
            return false
        }

        let outCounterpart = MovementRules.normaliseReference(outLeg.counterpartRef)
        let outReference = MovementRules.normaliseReference(outLeg.externalRef)
        let inCounterpart = MovementRules.normaliseReference(inLeg.counterpartRef)
        let inReference = MovementRules.normaliseReference(inLeg.externalRef)

        return (!outCounterpart.isEmpty && outCounterpart == inReference)
            || (!outReference.isEmpty && outReference == inCounterpart)
    }

    private func recordRate(
        from: Account,
        to: Account,
        amountOutMinor: Int64,
        amountInMinor: Int64,
        at date: Date
    ) {
        let out = Money(minorUnits: amountOutMinor, currency: from.currency)
        let inbound = Money(minorUnits: amountInMinor, currency: to.currency)
        guard out.minorUnits > 0 else {
            return
        }

        let decimalRate = inbound.decimalValue / out.decimalValue
        guard let rate = FXRate(base: out.currency, quote: inbound.currency, decimalRate: decimalRate) else {
            return
        }

        let record = ExchangeRateRecord(
            baseCode: out.currency.code,
            quoteCode: inbound.currency.code,
            rateScaled: rate.rateScaled,
            asOf: date,
            source: .transfer
        )
        context.insert(record)
    }
}
