//
//  StarterParseRules.swift
//  AppModels
//

import Foundation

nonisolated public struct SeedParseRule: Sendable {
    public let name: String
    public let messageType: LedgerEntryKind
    public let role: MessageRole
    public let pattern: String
    public let fieldPatterns: [String: String]
    public let sampleText: String

    public init(
        name: String,
        messageType: LedgerEntryKind,
        role: MessageRole = .transaction,
        pattern: String,
        fieldPatterns: [String: String] = [:],
        sampleText: String = ""
    ) {
        self.name = name
        self.messageType = messageType
        self.role = role
        self.pattern = pattern
        self.fieldPatterns = fieldPatterns
        self.sampleText = sampleText
    }
}

nonisolated public struct SeedParseRuleSet: Sendable {
    public let name: String
    public let seedKey: String
    public let senderMatchers: String
    public let priority: Int
    public let notes: String
    public let rules: [SeedParseRule]

    public init(
        name: String,
        seedKey: String,
        senderMatchers: String,
        priority: Int,
        notes: String,
        rules: [SeedParseRule]
    ) {
        self.name = name
        self.seedKey = seedKey
        self.senderMatchers = senderMatchers
        self.priority = priority
        self.notes = notes
        self.rules = rules
    }
}

public enum StarterParseRules {
    private static let amount = #"(?<amount>(?:KSH|KES|KSHS)\s?[\d,]+(?:\.\d{1,2})?)"#
    private static let balance = #"NEW M-PESA BALANCE IS\s*(?<balance>(?:KSH|KES|KSHS)\s?[\d,]+(?:\.\d{1,2})?)"#
    private static let fee = #"TRANSACTION COST,?\s*(?<fee>(?:KSH|KES|KSHS)\s?[\d,]+(?:\.\d{1,2})?)"#
    private static let mpesaStamp =
        #"\s+ON\s+(?<date>\d{1,2}/\d{1,2}/\d{2,4})\s+AT\s+(?<time>\d{1,2}:\d{2})\s*(?<ampm>[AP]M)"#

    public static let ruleSets: [SeedParseRuleSet] = [
        SeedParseRuleSet(
            name: "Mobile money",
            seedKey: "mpesa",
            senderMatchers: "M-PESA,MPESA,SAFARICOM",
            priority: 0,
            notes: "Mobile money confirmations.",
            rules: [
                SeedParseRule(
                    name: "Paid",
                    messageType: .expense,
                    pattern: #"^(?<ref>[A-Z0-9]{10})\s+CONFIRMED\.?\s+"# + amount
                        + #"\s+PAID\s+TO\s+(?<payee>.+?)\.?\s+ON\s+(?<date>\d{1,2}/\d{1,2}/\d{2,4})\s+AT\s+(?<time>\d{1,2}:\d{2})\s*(?<ampm>[AP]M)"#,
                    fieldPatterns: ["fee": fee, "balance": balance]
                ),
                SeedParseRule(
                    name: "Received from a bank",
                    messageType: .transferIn,
                    pattern: #"^(?<ref>[A-Z0-9]{10})\s+CONFIRMED\.?\s*YOU HAVE RECEIVED\s+"# + amount
                        + #"\s+FROM\s+(?<payee>IM BANK[^.]*?)"# + mpesaStamp,
                    fieldPatterns: ["balance": balance]
                ),
                SeedParseRule(
                    name: "Received",
                    messageType: .income,
                    pattern: #"^(?<ref>[A-Z0-9]{10})\s+CONFIRMED\.?\s*YOU HAVE RECEIVED\s+"# + amount
                        + #"\s+FROM\s+(?<payee>.+?)"# + mpesaStamp,
                    fieldPatterns: ["balance": balance]
                ),
            ]
        ),
        SeedParseRuleSet(
            name: "Bank",
            seedKey: "im-bank",
            senderMatchers: "IM BANK,IMBANK,I&M,PESALINK",
            priority: 1,
            notes: "Bank transaction alerts.",
            rules: [
                SeedParseRule(
                    name: "Bank to mobile money transfer",
                    messageType: .transferOut,
                    pattern: #"BANK TO M-PESA TRANSFER OF\s+"# + amount
                        + #"\s+TO\s+(?<payee>.+?)\s+SUCCESSFULLY PROCESSED\.?\s*TRANSACTION REF ID:\s*(?<ref>[A-Z0-9]+)\.?\s*M-PESA REF ID:\s*(?<counterpart>[A-Z0-9]+)"#,
                    // The destination wallet. Routing ignores this for a transfer-out, but
                    // ingest uses it to recognise the user's own M-PESA account.
                    fieldPatterns: ["account": #"TO\s+(?<account>\d{9,15})"#]
                ),
                SeedParseRule(
                    name: "Transfer to own account",
                    messageType: .transferOut,
                    pattern: #"TRANSFER TO OWN ACCOUNT OF\s+"# + amount
                        + #"\s+TO\s+(?<payee>.+?)\s+A/C\s+(?<account>\d+)(?:\s+ON\s+(?<date>\d{1,2}/\d{1,2}/\d{4})\s+(?<time>\d{1,2}:\d{2}))?\s+PROCESSED SUCCESSFULLY\.?\s*TRANSACTION REF ID:\s*(?<ref>[A-Z0-9]+)"#
                ),
                SeedParseRule(
                    name: "Bank transfer received",
                    messageType: .income,
                    pattern:
                        #"RECEIVED\s+(?<amount>KES\s?[\d,]+(?:\.\d{1,2})?)\s+VIA\s+PESALINK\s+INTO\s+ACC\s+(?<account>\d+)\s+TRAN REF\s+(?<ref>\d+)"#
                ),
                SeedParseRule(
                    name: "Card purchase",
                    messageType: .expense,
                    pattern:
                        #"MADE A PURCHASE OF\s*(?<amount>KES\s?[\d,]+(?:\.\d{1,2})?)(?:\s+ON\s+(?<date>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}))?\s+AT\s+(?<payee>.+?)\s+USING\s+[^.]*?\d{4}\*{4,}(?<cardLast4>\d{4})"#
                ),
            ]
        ),
    ]
}
