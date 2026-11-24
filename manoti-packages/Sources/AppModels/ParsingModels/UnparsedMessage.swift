//
//  UnparsedMessage.swift
//  AppModels
//

import Foundation
import SwiftData

/// A message the parser could not read. It is kept so a bank alert is never silently
/// dropped; it never affects balances.
@Model
public final class UnparsedMessage {
    public var id: UUID = UUID()
    public var rawText: String = ""
    public var sender: String = ""
    public var receivedAt: Date = Date()
    public var reason: String = ""
    public var dedupeHash: String = ""
    public var createdAt: Date = Date()
    /// Kept when the user dismisses the row, so the same message shape is not new work.
    public var isDismissed: Bool = false

    public init(
        rawText: String,
        sender: String = "",
        receivedAt: Date = Date(),
        reason: String = "",
        dedupeHash: String = ""
    ) {
        self.id = UUID()
        self.rawText = rawText
        self.sender = sender
        self.receivedAt = receivedAt
        self.reason = reason
        self.dedupeHash = dedupeHash
        self.createdAt = Date()
    }
}
