//
//  Tag.swift
//  AppModels
//

import Foundation
import SwiftData

/// A free-text purpose label attached to ledger lines: an invoice number, a job name,
/// anything the user wants to track money in and out of.
///
/// A tag never moves money and never changes a balance. Its totals are derived from the
/// lines that carry it, read by `TagService`.
@Model
public final class Tag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var note: String = ""
    public var colorHex: String = "#2F80ED"
    public var symbolName: String = "tag"
    public var statusRaw: String = TagStatus.open.rawValue
    public var closedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntryLine.tags)
    public var lines: [LedgerEntryLine]?

    public init(
        name: String,
        colorHex: String = "#2F80ED",
        symbolName: String = "tag",
        note: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var status: TagStatus {
        get { TagStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    public var isOpen: Bool {
        status == .open
    }
}
