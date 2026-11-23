//
//  Transfer.swift
//  AppModels
//

import Foundation
import SwiftData

/// Groups the two ledger legs of one movement between two of the user's own accounts.
/// The fee lives on the out-leg transaction, never here, so it is counted exactly once.
@Model
public final class Transfer {
    public var id: UUID = UUID()
    public var occurredAt: Date = Date()
    public var statusRaw: String = TransferStatus.confirmed.rawValue
    public var note: String = ""
    public var createdAt: Date = Date()

    public var fromAccount: Account?
    public var toAccount: Account?

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.transfer)
    public var legs: [LedgerEntry]?

    public init(occurredAt: Date = Date(), note: String = "") {
        self.id = UUID()
        self.occurredAt = occurredAt
        self.note = note
        self.createdAt = Date()
    }

    public var status: TransferStatus {
        get { TransferStatus(rawValue: statusRaw) ?? .confirmed }
        set { statusRaw = newValue.rawValue }
    }

    public var outTransaction: LedgerEntry? {
        legs?.first { $0.kind == .transferOut }
    }

    public var inTransaction: LedgerEntry? {
        legs?.first { $0.kind == .transferIn }
    }

    public var fee: Money? {
        guard let outTransaction else {
            return nil
        }

        return outTransaction.fee
    }

    /// Derived for display only; the two legs' minor units are the ground truth.
    public var rate: FXRate? {
        guard let outTransaction, let inTransaction,
            outTransaction.amountMinor != 0
        else {
            return nil
        }

        let out = outTransaction.amount
        let inbound = inTransaction.amount
        guard out.minorUnits > 0 else {
            return nil
        }

        let decimalRate = inbound.decimalValue / out.decimalValue
        return FXRate(base: out.currency, quote: inbound.currency, decimalRate: decimalRate)
    }
}
