//
//  ExchangeRateService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum ExchangeRateError: Error, Equatable {
    case sameCurrency
    case invalidRate
    case transferRate
}

/// One row in the Settings rate list: the newest record for a currency pair.
nonisolated public struct ExchangeRateSummary: Identifiable, Sendable {
    public let recordID: UUID
    public let base: Currency
    public let quote: Currency
    public let rate: FXRate
    public let asOf: Date
    public let source: ExchangeRateSource

    public var id: String {
        "\(base.code)>\(quote.code)"
    }

    public init(
        recordID: UUID,
        base: Currency,
        quote: Currency,
        rate: FXRate,
        asOf: Date,
        source: ExchangeRateSource
    ) {
        self.recordID = recordID
        self.base = base
        self.quote = quote
        self.rate = rate
        self.asOf = asOf
        self.source = source
    }
}

/// Reads and writes the global, per-pair exchange rates used for display conversion.
@Observable
public final class ExchangeRateService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func rateBook() throws -> ExchangeRateBook {
        ExchangeRateBook(records: try fetchRecords())
    }

    /// The newest record for each ordered pair, ready for the Settings list.
    public func latestRates() throws -> [ExchangeRateSummary] {
        var seen: Set<String> = []
        var summaries: [ExchangeRateSummary] = []

        for record in try fetchRecords() {
            let key = "\(record.baseCode)>\(record.quoteCode)"
            guard !seen.contains(key), let rate = record.rate else {
                continue
            }

            seen.insert(key)
            summaries.append(
                ExchangeRateSummary(
                    recordID: record.id,
                    base: rate.base,
                    quote: rate.quote,
                    rate: rate,
                    asOf: record.asOf,
                    source: record.source
                )
            )
        }

        return summaries.sorted {
            ($0.base.code, $0.quote.code) < ($1.base.code, $1.quote.code)
        }
    }

    /// Adds a manual rate. The newest `asOf` wins, so a later entry corrects an earlier one.
    ///
    /// A future `asOf` is clamped to the start of today: a manual rate may describe today or
    /// the past, but never post-date the present and affect conversions retroactively.
    @discardableResult
    public func addRate(
        base: Currency,
        quote: Currency,
        decimalRate: Decimal,
        asOf: Date = Date(),
        calendar: Calendar = .current,
        now: Date = Date()
    ) throws -> ExchangeRateRecord {
        guard base != quote else {
            throw ExchangeRateError.sameCurrency
        }

        guard let rate = FXRate(base: base, quote: quote, decimalRate: decimalRate) else {
            throw ExchangeRateError.invalidRate
        }

        let effectiveDate = min(asOf, calendar.startOfDay(for: now))
        let record = ExchangeRateRecord(
            baseCode: base.code,
            quoteCode: quote.code,
            rateScaled: rate.rateScaled,
            asOf: effectiveDate,
            source: .manual
        )
        context.insert(record)
        try context.save()
        ManotiNotifications.postDataChanged()
        return record
    }

    /// Removes a mistyped manual rate. A rate captured from a transfer is history and stays.
    public func deleteRate(_ record: ExchangeRateRecord) throws {
        guard record.source == .manual else {
            throw ExchangeRateError.transferRate
        }

        context.delete(record)
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    public func deleteRate(id: UUID) throws {
        var descriptor = FetchDescriptor<ExchangeRateRecord>(
            predicate: #Predicate<ExchangeRateRecord> { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let record = try context.fetch(descriptor).first else {
            return
        }

        try deleteRate(record)
    }

    private func fetchRecords() throws -> [ExchangeRateRecord] {
        let records = try context.fetch(FetchDescriptor<ExchangeRateRecord>())
        let calendar = Calendar.current

        return records.sorted { lhs, rhs in
            let lhsDay = calendar.startOfDay(for: lhs.asOf)
            let rhsDay = calendar.startOfDay(for: rhs.asOf)

            if lhsDay != rhsDay {
                return lhsDay > rhsDay
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}
