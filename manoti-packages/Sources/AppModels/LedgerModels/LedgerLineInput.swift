//
//  LedgerLineInput.swift
//  AppModels
//

import Foundation

/// The service-level shape of one line when recording or updating an entry.
///
/// Main-actor by default because it references SwiftData models.
public struct LedgerLineInput {
    public var amountMinor: Int64
    public var category: SpendingCategory?
    public var tags: [Tag]

    public init(
        amountMinor: Int64,
        category: SpendingCategory? = nil,
        tags: [Tag] = []
    ) {
        self.amountMinor = amountMinor
        self.category = category
        self.tags = tags
    }
}
