//
//  ExchangeRateRecord.swift
//  AppModels
//

import Foundation
import SwiftData

nonisolated public enum ExchangeRateSource: String, CaseIterable, Codable, Sendable {
    case manual
    case transfer
}

/// A dated, scaled major-unit rate for one currency pair.
@Model
public final class ExchangeRateRecord {
    public var id: UUID = UUID()
    public var baseCode: String = CurrencyCatalog.defaultCurrency.code
    public var quoteCode: String = "USD"
    public var rateScaled: Int64 = FXRate.scale
    public var asOf: Date = Date()
    public var sourceRaw: String = ExchangeRateSource.manual.rawValue
    public var createdAt: Date = Date()

    public init(
        baseCode: String,
        quoteCode: String,
        rateScaled: Int64,
        asOf: Date = Date(),
        source: ExchangeRateSource = .manual
    ) {
        self.id = UUID()
        self.baseCode = baseCode.uppercased()
        self.quoteCode = quoteCode.uppercased()
        self.rateScaled = rateScaled
        self.asOf = asOf
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
    }

    public var source: ExchangeRateSource {
        get { ExchangeRateSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var rate: FXRate? {
        FXRate(
            base: CurrencyCatalog.currency(for: baseCode),
            quote: CurrencyCatalog.currency(for: quoteCode),
            rateScaled: rateScaled
        )
    }
}
