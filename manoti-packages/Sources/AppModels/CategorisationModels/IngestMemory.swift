//
//  IngestMemory.swift
//  AppModels
//

import Foundation
import SwiftData

nonisolated public enum IngestMemoryReason: String, CaseIterable, Codable, Sendable {
    case notATransaction
    case duplicate

    public var displayName: String {
        switch self {
            case .notATransaction: "Not a transaction"
            case .duplicate: "Already recorded"
        }
    }
}

/// What the user taught the app about one message shape.
///
/// One row per sender + template. `reason` decides whether ingest suppresses the
/// message or surfaces it as a repeat. Nothing here is derived from raw text: only the
/// fingerprint is kept, so it survives with message retention off.
@Model
public final class IngestMemory {
    public var id: UUID = UUID()
    public var sender: String = ""
    public var fingerprint: String = ""
    public var reasonRaw: String = IngestMemoryReason.notATransaction.rawValue
    public var amountMinor: Int64 = -1
    public var kindRaw: String = ""
    public var externalRef: String = ""
    public var hitCount: Int = 0
    public var lastSeenAt: Date = Date()
    public var createdAt: Date = Date()

    public init(sender: String, fingerprint: String, reason: IngestMemoryReason) {
        self.id = UUID()
        self.sender = sender
        self.fingerprint = fingerprint
        self.reasonRaw = reason.rawValue
        self.hitCount = 0
        self.lastSeenAt = Date()
        self.createdAt = Date()
    }

    public var reason: IngestMemoryReason {
        get { IngestMemoryReason(rawValue: reasonRaw) ?? .notATransaction }
        set { reasonRaw = newValue.rawValue }
    }
}
