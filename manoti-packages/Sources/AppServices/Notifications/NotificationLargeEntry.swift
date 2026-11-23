//
//  NotificationLargeEntry.swift
//  AppServices
//

import Foundation

/// The newest posted expense discovered since the previous scheduling pass.
nonisolated public struct NotificationLargeEntry: Sendable, Equatable {
    public var entryID: UUID
    public var amountMinor: Int64
    public var currencyCode: String
    public var payee: String
    public var occurredAt: Date

    public init(entryID: UUID, amountMinor: Int64, currencyCode: String, payee: String, occurredAt: Date) {
        self.entryID = entryID
        self.amountMinor = amountMinor
        self.currencyCode = currencyCode
        self.payee = payee
        self.occurredAt = occurredAt
    }
}
