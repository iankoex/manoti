//
//  ParseRule.swift
//  AppModels
//

import Foundation
import SwiftData

@Model
public final class ParseRule {
    public var id: UUID = UUID()
    public var name: String = ""
    public var messageTypeRaw: String = LedgerEntryKind.expense.rawValue
    /// Whether this rule records a movement or confirms one another message records.
    public var roleRaw: String = MessageRole.transaction.rawValue
    /// Full classification regex with named groups.
    public var pattern: String = ""
    /// JSON object of extra field name → regex, for optional clauses such as fee or balance.
    public var fieldPatternsJSON: String = "{}"
    public var priority: Int = 0
    public var isEnabled: Bool = true
    public var sampleText: String = ""
    public var ruleSet: ParseRuleSet?

    public init(
        name: String,
        messageType: LedgerEntryKind,
        role: MessageRole = .transaction,
        pattern: String,
        fieldPatterns: [String: String] = [:],
        priority: Int = 0,
        sampleText: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.messageTypeRaw = messageType.rawValue
        self.roleRaw = role.rawValue
        self.pattern = pattern
        self.fieldPatternsJSON = Self.encode(fieldPatterns)
        self.priority = priority
        self.sampleText = sampleText
    }

    public var messageType: LedgerEntryKind {
        get { LedgerEntryKind(rawValue: messageTypeRaw) ?? .expense }
        set { messageTypeRaw = newValue.rawValue }
    }

    public var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .transaction }
        set { roleRaw = newValue.rawValue }
    }

    public var fieldPatterns: [String: String] {
        get {
            guard let data = fieldPatternsJSON.data(using: .utf8),
                let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                return [:]
            }

            return decoded
        }
        set {
            fieldPatternsJSON = Self.encode(newValue)
        }
    }

    private static func encode(_ patterns: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(patterns),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return text
    }
}
