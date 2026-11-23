//
//  TransferService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum TransferError: Error, Equatable {
    case sameAccount
    case invalidAmount
    case amountInRequired
    case amountMismatch
    case archivedAccount
    case alreadyLinked
    case wrongLegKinds
    case timeMismatch
}

extension TransferError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .sameAccount:
                return "Choose two different accounts."
            case .invalidAmount:
                return "Enter an amount greater than zero."
            case .amountInRequired:
                return "Enter the amount received in the destination currency."
            case .amountMismatch:
                return "A same-currency transfer must receive the amount that was sent."
            case .archivedAccount:
                return "That account is archived. Choose an active account."
            case .alreadyLinked:
                return "One of these entries is already part of a transfer."
            case .wrongLegKinds:
                return "Link one transfer out to one transfer in."
            case .timeMismatch:
                return "The two entries are more than 15 minutes apart. Check the reference before linking them."
        }
    }
}

/// One possible opposite leg for an unpaired transfer entry, with the reason it matched.
///
/// `LedgerEntry` is a SwiftData class, so the candidate is deliberately not `Sendable`.
public struct TransferLinkCandidate: Identifiable, Equatable {
    public enum Reason: Equatable, Sendable {
        case reference
        case amountAndTime
    }

    public let entry: LedgerEntry
    public let reason: Reason
    public let timeDifference: TimeInterval

    public var id: UUID { entry.id }

    public init(entry: LedgerEntry, reason: Reason, timeDifference: TimeInterval) {
        self.entry = entry
        self.reason = reason
        self.timeDifference = timeDifference
    }

    public static func == (lhs: TransferLinkCandidate, rhs: TransferLinkCandidate) -> Bool {
        lhs.entry.id == rhs.entry.id && lhs.reason == rhs.reason && lhs.timeDifference == rhs.timeDifference
    }
}

@Observable
public final class TransferService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func transfer(
        from: Account,
        to: Account,
        amountOutMinor: Int64,
        amountInMinor: Int64? = nil,
        feeMinor: Int64 = 0,
        occurredAt: Date = Date(),
        note: String = ""
    ) throws -> Transfer {
        guard from.id != to.id else {
            throw TransferError.sameAccount
        }

        guard amountOutMinor > 0, feeMinor >= 0 else {
            throw TransferError.invalidAmount
        }

        guard !from.isArchived, !to.isArchived else {
            throw TransferError.archivedAccount
        }

        let resolvedAmountIn: Int64

        if from.currency == to.currency {
            resolvedAmountIn = amountInMinor ?? amountOutMinor
            guard resolvedAmountIn == amountOutMinor else {
                throw TransferError.amountMismatch
            }
        } else {
            guard let amountInMinor, amountInMinor > 0 else {
                throw TransferError.amountInRequired
            }
            resolvedAmountIn = amountInMinor
        }

        let transfer = Transfer(occurredAt: occurredAt, note: note)
        transfer.fromAccount = from
        transfer.toAccount = to
        context.insert(transfer)

        let outLeg = LedgerEntry(
            kind: .transferOut,
            amountMinor: amountOutMinor,
            feeMinor: feeMinor,
            currencyCode: from.currencyCode,
            occurredAt: occurredAt,
            note: note
        )
        outLeg.account = from
        outLeg.transfer = transfer
        context.insert(outLeg)

        let inLeg = LedgerEntry(
            kind: .transferIn,
            amountMinor: resolvedAmountIn,
            currencyCode: to.currencyCode,
            occurredAt: occurredAt,
            note: note
        )
        inLeg.account = to
        inLeg.transfer = transfer
        context.insert(inLeg)

        if from.currency != to.currency {
            recordRate(
                from: from, to: to, amountOutMinor: amountOutMinor, amountInMinor: resolvedAmountIn, at: occurredAt)
        }

        try context.save()
        ManotiNotifications.postDataChanged()
        return transfer
    }

    /// Transfer legs that do not yet belong to a `Transfer`.
    ///
    /// Review rows are included: the money has moved, so they should be pairable even while
    /// their category or account still needs attention. Soft-deleted and ignored rows are not.
    public func unpairedLegs() throws -> [LedgerEntry] {
        let descriptor = FetchDescriptor<LedgerEntry>(
            sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { entry in
            entry.kind.isTransferLeg && entry.transfer == nil && entry.isPosted
        }
    }

    /// Opposite-direction legs that could be joined to `leg`, strongest match first.
    public func linkCandidates(for leg: LedgerEntry) throws -> [TransferLinkCandidate] {
        guard leg.transfer == nil, leg.kind.isTransferLeg, let legAccount = leg.account else {
            return []
        }

        let oppositeKind: LedgerEntryKind = leg.kind == .transferOut ? .transferIn : .transferOut
        let descriptor = FetchDescriptor<LedgerEntry>(
            sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
        )
        let entries = try context.fetch(descriptor)

        var candidates: [TransferLinkCandidate] = []

        for entry in entries {
            guard entry.id != leg.id,
                entry.kind == oppositeKind,
                entry.transfer == nil,
                entry.isPosted,
                let candidateAccount = entry.account,
                candidateAccount.id != legAccount.id
            else {
                continue
            }

            let difference = abs(leg.occurredAt.timeIntervalSince(entry.occurredAt))
            let outLeg = leg.kind == .transferOut ? leg : entry
            let inLeg = leg.kind == .transferIn ? leg : entry

            if referenceMatches(outLeg: outLeg, inLeg: inLeg) {
                candidates.append(
                    TransferLinkCandidate(entry: entry, reason: .reference, timeDifference: difference))
                continue
            }

            guard difference <= TransferService.matchWindow,
                amountMatches(outLeg: outLeg, inLeg: inLeg)
            else {
                continue
            }

            candidates.append(
                TransferLinkCandidate(entry: entry, reason: .amountAndTime, timeDifference: difference))
        }

        return candidates.sorted { lhs, rhs in
            if lhs.reason != rhs.reason {
                return lhs.reason == .reference
            }

            if lhs.timeDifference != rhs.timeDifference {
                return lhs.timeDifference < rhs.timeDifference
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Transfers whose out and in legs both still exist, newest first.
    public func linkedTransfers() throws -> [Transfer] {
        let descriptor = FetchDescriptor<Transfer>(
            sortBy: [SortDescriptor(\Transfer.occurredAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { transfer in
            guard let outLeg = transfer.outTransaction, let inLeg = transfer.inTransaction else {
                return false
            }

            return !outLeg.isSoftDeleted && !inLeg.isSoftDeleted
        }
    }

    @discardableResult
    public func link(outLeg: LedgerEntry, inLeg: LedgerEntry) throws -> Transfer {
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
            abs(outLeg.occurredAt.timeIntervalSince(inLeg.occurredAt)) > TransferService.matchWindow
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
        ManotiNotifications.postDataChanged()
        return transfer
    }

    public func unlink(_ transfer: Transfer) throws {
        removeCapturedRate(for: transfer)

        for leg in transfer.legs ?? [] {
            leg.transfer = nil
        }

        context.delete(transfer)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    /// Removes a transfer and soft-deletes both legs. Unlink keeps the legs for repair;
    /// deleting means the movement itself was wrong.
    public func delete(_ transfer: Transfer) throws {
        removeCapturedRate(for: transfer)

        for leg in transfer.legs ?? [] {
            leg.isSoftDeleted = true
            leg.transfer = nil
        }

        context.delete(transfer)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    private func removeCapturedRate(for transfer: Transfer) {
        guard let out = (transfer.legs ?? []).first(where: { $0.kind == .transferOut }),
            let inbound = (transfer.legs ?? []).first(where: { $0.kind == .transferIn }),
            let from = out.account,
            let to = inbound.account,
            from.currency != to.currency
        else {
            return
        }

        let base = from.currencyCode
        let quote = to.currencyCode
        let date = transfer.occurredAt
        let records = (try? context.fetch(FetchDescriptor<ExchangeRateRecord>())) ?? []

        for record in records
        where record.sourceRaw == ExchangeRateSource.transfer.rawValue
            && record.baseCode == base
            && record.quoteCode == quote
            && abs(record.asOf.timeIntervalSince(date)) < 1
        {
            context.delete(record)
        }
    }

    private static let matchWindow: TimeInterval = 15 * 60
    private static let amountTolerance = 0.01

    /// True when one leg names the other's reference, in either direction.
    private func referenceMatches(outLeg: LedgerEntry, inLeg: LedgerEntry) -> Bool {
        guard outLeg.kind == .transferOut, inLeg.kind == .transferIn else {
            return false
        }

        let outCounterpart = outLeg.counterpartRef
        let outReference = outLeg.externalRef
        let inCounterpart = inLeg.counterpartRef
        let inReference = inLeg.externalRef

        return (!outCounterpart.isEmpty && outCounterpart == inReference)
            || (!outReference.isEmpty && outReference == inCounterpart)
    }

    /// The reconciliation convention: the out total (amount + fee) is within 1% of the
    /// incoming amount. The in-leg fee is also tolerated, because some banks deduct it there.
    private func amountMatches(outLeg: LedgerEntry, inLeg: LedgerEntry) -> Bool {
        guard outLeg.currencyCode == inLeg.currencyCode else {
            return false
        }

        let outTotal = outLeg.amountMinor + outLeg.feeMinor
        let inAmount = inLeg.amountMinor
        guard outTotal > 0, inAmount > 0 else {
            return false
        }

        let tolerance = Double(inAmount) * TransferService.amountTolerance
        if abs(Double(outTotal - inAmount)) <= tolerance {
            return true
        }

        let inNet = inAmount - inLeg.feeMinor
        return inNet > 0 && abs(Double(outTotal - inNet)) <= tolerance
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
