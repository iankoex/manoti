//
//  ParsedMessage.swift
//  AppModels
//

import Foundation

/// The result of reading one bank or mobile-money message. No persistence decisions yet.
nonisolated public struct ParsedMessage: Sendable, Equatable {
    public var ruleSetName: String
    public var ruleName: String
    public var messageType: LedgerEntryKind
    public var role: MessageRole
    public var amountMinor: Int64
    public var currencyCode: String
    public var feeMinor: Int64
    public var payee: String
    public var reference: String
    public var counterpartReference: String
    public var accountHint: String
    public var cardLast4: String
    public var balanceAfterMinor: Int64?
    public var occurredAt: Date
    public var dateFromMessage: Bool
    public var confidence: Double
    public var rawText: String
    public var sender: String

    public init(
        ruleSetName: String,
        ruleName: String,
        messageType: LedgerEntryKind,
        role: MessageRole = .transaction,
        amountMinor: Int64,
        currencyCode: String,
        feeMinor: Int64 = 0,
        payee: String = "",
        reference: String = "",
        counterpartReference: String = "",
        accountHint: String = "",
        cardLast4: String = "",
        balanceAfterMinor: Int64? = nil,
        occurredAt: Date,
        dateFromMessage: Bool,
        confidence: Double,
        rawText: String,
        sender: String = ""
    ) {
        self.ruleSetName = ruleSetName
        self.ruleName = ruleName
        self.messageType = messageType
        self.role = role
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.feeMinor = feeMinor
        self.payee = payee
        self.reference = reference
        self.counterpartReference = counterpartReference
        self.accountHint = accountHint
        self.cardLast4 = cardLast4
        self.balanceAfterMinor = balanceAfterMinor
        self.occurredAt = occurredAt
        self.dateFromMessage = dateFromMessage
        self.confidence = confidence
        self.rawText = rawText
        self.sender = sender
    }
}

nonisolated public enum ParseOutcome: Sendable, Equatable {
    case parsed(ParsedMessage)
    case unrecognised(rawText: String)
}
