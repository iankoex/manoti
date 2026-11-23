//
//  ReconcileMessage.swift
//  AppModels
//

import Foundation
import SwiftData

/// One bank or mobile-money message collected during a reconciliation session.
///
/// The parsed fields are flattened onto the row so a message survives without re-parsing and
/// the summary can count messages the parser could not read (`parsedKindRaw == ""`).
@Model
public final class ReconcileMessage {
    public var id: UUID = UUID()
    public var session: ReconcileSession?
    public var text: String = ""
    public var sender: String = ""
    public var receivedAt: Date?
    public var parsedKindRaw: String = ""
    public var amountMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code
    public var feeMinor: Int64 = 0
    public var payee: String = ""
    public var reference: String = ""
    public var accountHint: String = ""
    public var occurredAt: Date?
    public var dateFromMessage: Bool = false
    public var confidence: Double = 0
    public var classificationRaw: String = ReconcileClassification.pending.rawValue
    public var matchedEntryID: UUID?
    public var createdAt: Date = Date()
    public var dedupeHash: String = ""

    public init(
        text: String,
        sender: String = "",
        receivedAt: Date? = nil,
        parsedKind: LedgerEntryKind? = nil,
        amountMinor: Int64 = 0,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        feeMinor: Int64 = 0,
        payee: String = "",
        reference: String = "",
        accountHint: String = "",
        occurredAt: Date? = nil,
        dateFromMessage: Bool = false,
        confidence: Double = 0,
        classification: ReconcileClassification = .pending,
        dedupeHash: String = ""
    ) {
        self.id = UUID()
        self.text = text
        self.sender = sender
        self.receivedAt = receivedAt
        self.parsedKindRaw = parsedKind?.rawValue ?? ""
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.feeMinor = feeMinor
        self.payee = payee
        self.reference = reference
        self.accountHint = accountHint
        self.occurredAt = occurredAt
        self.dateFromMessage = dateFromMessage
        self.confidence = confidence
        self.classificationRaw = classification.rawValue
        self.createdAt = Date()
        self.dedupeHash = dedupeHash
    }

    public var parsedKind: LedgerEntryKind? {
        LedgerEntryKind(rawValue: parsedKindRaw)
    }

    public var classification: ReconcileClassification {
        get { ReconcileClassification(rawValue: classificationRaw) ?? .pending }
        set { classificationRaw = newValue.rawValue }
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    /// The amount the message says moved, including any fee it paid.
    public var totalAmountMinor: Int64 {
        amountMinor + feeMinor
    }
}
