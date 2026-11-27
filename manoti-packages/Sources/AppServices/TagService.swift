//
//  TagService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum TagError: Error, Equatable {
    case emptyName
    case duplicateName
    case inUse(lineCount: Int)
}

extension TagError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .emptyName:
                return "Give the tag a name."
            case .duplicateName:
                return "A tag with that name already exists."
            case .inUse(let lineCount):
                return "This tag is used by \(lineCount) line\(lineCount == 1 ? "" : "s"). Close it instead."
        }
    }
}

/// A tag's money, converted into one display currency.
nonisolated public struct TagSummary: Equatable, Sendable {
    public let received: Money
    public let spent: Money
    public let balance: Money
    public let lineCount: Int
    public let missingRates: [String]

    public var profit: Money { balance }

    public init(
        received: Money,
        spent: Money,
        balance: Money,
        lineCount: Int,
        missingRates: [String]
    ) {
        self.received = received
        self.spent = spent
        self.balance = balance
        self.lineCount = lineCount
        self.missingRates = missingRates
    }
}

/// One entry that carries a tag, with the amount this tag is responsible for.
@MainActor
public struct TaggedEntry: Identifiable {
    public let entry: LedgerEntry
    public let amountMinor: Int64

    public var id: UUID { entry.id }

    public init(entry: LedgerEntry, amountMinor: Int64) {
        self.entry = entry
        self.amountMinor = amountMinor
    }
}

/// Creates, closes and totals tags. A tag never moves money; everything here is derived
/// from the lines that carry it.
@Observable
public final class TagService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Tags

    public func fetchTags(includeClosed: Bool = false) throws -> [Tag] {
        let tags = try context.fetch(FetchDescriptor<Tag>())
        return tags
            .filter { includeClosed || $0.isOpen }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status == .open
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    @discardableResult
    public func createTag(
        name: String,
        colorHex: String = "#2F80ED",
        symbolName: String = "tag",
        note: String = ""
    ) throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TagError.emptyName
        }

        try ensureUnique(trimmed, excluding: nil)

        let tag = Tag(name: trimmed, colorHex: colorHex, symbolName: symbolName, note: note)
        context.insert(tag)
        try context.save()
        ManotiNotifications.postDataChanged()
        return tag
    }

    public func updateTag(
        _ tag: Tag,
        name: String,
        colorHex: String,
        symbolName: String,
        note: String
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TagError.emptyName
        }

        try ensureUnique(trimmed, excluding: tag.id)

        tag.name = trimmed
        tag.colorHex = colorHex
        tag.symbolName = symbolName
        tag.note = note
        tag.updatedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func closeTag(_ tag: Tag, at date: Date = Date()) throws {
        tag.status = .closed
        tag.closedAt = date
        tag.updatedAt = date
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func reopenTag(_ tag: Tag) throws {
        tag.status = .open
        tag.closedAt = nil
        tag.updatedAt = Date()
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func deleteTag(_ tag: Tag) throws {
        let lineCount = (tag.lines ?? []).filter { line in
            guard let entry = line.entry else {
                return false
            }

            return entry.isPosted && entry.status == .confirmed
        }.count

        guard lineCount == 0 else {
            throw TagError.inUse(lineCount: lineCount)
        }

        context.delete(tag)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    // MARK: - Totals

    public func summary(
        for tag: Tag,
        displayCurrency: Currency,
        asOf _: Date = Date()
    ) throws -> TagSummary {
        let book = try rateBook()
        var received: Int64 = 0
        var spent: Int64 = 0
        var missing: Set<String> = []
        var lineCount = 0

        for line in tag.lines ?? [] {
            guard let entry = line.entry, entry.isPosted, entry.status == .confirmed else {
                continue
            }

            let money = Money(minorUnits: line.amountMinor, currency: entry.currency)
            let converted: Money

            if let value = book.convert(money, to: displayCurrency, on: entry.occurredAt) {
                converted = value
            } else {
                missing.insert(entry.currency.code)
                converted = fallback(money, to: displayCurrency)
            }

            lineCount += 1

            switch entry.kind {
                case .income:
                    received += converted.minorUnits
                case .expense:
                    spent += converted.minorUnits
                default:
                    break
            }
        }

        return TagSummary(
            received: Money(minorUnits: received, currency: displayCurrency),
            spent: Money(minorUnits: spent, currency: displayCurrency),
            balance: Money(minorUnits: received - spent, currency: displayCurrency),
            lineCount: lineCount,
            missingRates: missing.sorted()
        )
    }

    /// The entries behind a tag, newest first, each with the amount this tag is responsible for.
    public func entries(for tag: Tag) throws -> [TaggedEntry] {
        var totals: [UUID: (entry: LedgerEntry, amountMinor: Int64)] = [:]

        for line in tag.lines ?? [] {
            guard let entry = line.entry, entry.isPosted, entry.status == .confirmed else {
                continue
            }

            if var existing = totals[entry.id] {
                existing.amountMinor += line.amountMinor
                totals[entry.id] = existing
            } else {
                totals[entry.id] = (entry, line.amountMinor)
            }
        }

        return totals.values
            .map { TaggedEntry(entry: $0.entry, amountMinor: $0.amountMinor) }
            .sorted { lhs, rhs in
                if lhs.entry.occurredAt != rhs.entry.occurredAt {
                    return lhs.entry.occurredAt > rhs.entry.occurredAt
                }

                return lhs.entry.id.uuidString < rhs.entry.id.uuidString
            }
    }

    // MARK: - Helpers

    private func ensureUnique(_ name: String, excluding id: UUID?) throws {
        let existing = try context.fetch(FetchDescriptor<Tag>())

        for tag in existing where tag.id != id {
            if tag.name.localizedCaseInsensitiveCompare(name) == .orderedSame {
                throw TagError.duplicateName
            }
        }
    }

    private func rateBook() throws -> ExchangeRateBook {
        let records = try context.fetch(
            FetchDescriptor<ExchangeRateRecord>(sortBy: [SortDescriptor(\ExchangeRateRecord.asOf, order: .reverse)])
        )
        return ExchangeRateBook(records: records)
    }

    /// Missing rates are shown 1:1 in major units, matching the insights convention.
    private func fallback(_ money: Money, to currency: Currency) -> Money {
        guard money.currency.code != currency.code else {
            return money
        }

        let major = Decimal(money.minorUnits) / pow(10, money.currency.exponent)
        let scaled = major * pow(10, currency.exponent)
        return Money(minorUnits: NSDecimalNumber(decimal: scaled).int64Value, currency: currency)
    }
}
