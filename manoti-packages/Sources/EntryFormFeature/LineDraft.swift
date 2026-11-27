//
//  LineDraft.swift
//  EntryFormFeature
//

import Foundation

/// One editable line in the split editor. The amount is text so the user can type it with
/// the decimal keyboard; the state parses it when validating and saving.
public struct LineDraft: Identifiable, Equatable {
    public let id: UUID
    public var amountText: String
    public var categoryID: UUID?
    public var tagIDs: Set<UUID>

    public init(
        id: UUID = UUID(),
        amountText: String = "",
        categoryID: UUID? = nil,
        tagIDs: Set<UUID> = []
    ) {
        self.id = id
        self.amountText = amountText
        self.categoryID = categoryID
        self.tagIDs = tagIDs
    }
}
