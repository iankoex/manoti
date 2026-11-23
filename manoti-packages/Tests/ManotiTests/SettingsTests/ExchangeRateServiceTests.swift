//
//  ExchangeRateServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("ExchangeRateService")
struct ExchangeRateServiceTests {
    private func makeService() throws -> (ExchangeRateService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return (ExchangeRateService(context: context), context)
    }

    @Test("A manual rate converts through the exponent-aware book")
    func addRate() throws {
        let (service, _) = try makeService()
        let rate = try #require(Decimal(string: "129.03"))

        try service.addRate(base: .usd, quote: .kes, decimalRate: rate)

        let converted = try service.rateBook().convert(
            Money(minorUnits: 10_000, currency: .usd),
            to: .kes
        )

        #expect(converted?.minorUnits == 1_290_300)
    }

    @Test("The newest rate for a pair wins")
    func newestWins() throws {
        let (service, _) = try makeService()

        try service.addRate(
            base: .usd,
            quote: .kes,
            decimalRate: 100,
            asOf: Date(timeIntervalSince1970: 100)
        )
        try service.addRate(
            base: .usd,
            quote: .kes,
            decimalRate: 130,
            asOf: Date(timeIntervalSince1970: 200)
        )

        let rate = try service.rateBook().rate(from: .usd, to: .kes)

        #expect(rate?.rateScaled == 130_000_000)
    }

    @Test("A manual rate overrides an older rate captured from a transfer")
    func manualOverridesTransfer() throws {
        let (service, context) = try makeService()

        context.insert(
            ExchangeRateRecord(
                baseCode: "USD",
                quoteCode: "KES",
                rateScaled: 100_000_000,
                asOf: Date(timeIntervalSince1970: 100),
                source: .transfer
            )
        )
        try context.save()

        try service.addRate(
            base: .usd,
            quote: .kes,
            decimalRate: 130,
            asOf: Date(timeIntervalSince1970: 200)
        )

        #expect(try service.rateBook().rate(from: .usd, to: .kes)?.rateScaled == 130_000_000)
    }

    @Test("A rate needs two currencies and a positive value")
    func validation() throws {
        let (service, _) = try makeService()

        #expect(throws: ExchangeRateError.sameCurrency) {
            try service.addRate(base: .kes, quote: .kes, decimalRate: 1)
        }
        #expect(throws: ExchangeRateError.invalidRate) {
            try service.addRate(base: .usd, quote: .kes, decimalRate: 0)
        }
    }

    @Test("Latest rates lists one row per currency pair")
    func latestRates() throws {
        let (service, context) = try makeService()

        try service.addRate(
            base: .usd,
            quote: .kes,
            decimalRate: 100,
            asOf: Date(timeIntervalSince1970: 100)
        )
        try service.addRate(
            base: .usd,
            quote: .kes,
            decimalRate: 130,
            asOf: Date(timeIntervalSince1970: 200)
        )
        context.insert(
            ExchangeRateRecord(
                baseCode: "GBP",
                quoteCode: "KES",
                rateScaled: 170_000_000,
                asOf: Date(timeIntervalSince1970: 150)
            )
        )
        try context.save()

        let summaries = try service.latestRates()

        #expect(summaries.count == 2)
        #expect(summaries.contains { $0.base.code == "USD" && $0.rate.rateScaled == 130_000_000 })
        #expect(summaries.contains { $0.base.code == "GBP" })
    }

    @Test("A later manual rate on the same day is listed and wins")
    func sameDayManualListed() throws {
        let (service, context) = try makeService()
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

        let transfer = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 130_000_000,
            asOf: day.addingTimeInterval(14 * 3_600),
            source: .transfer
        )
        transfer.createdAt = day.addingTimeInterval(8 * 3_600)
        context.insert(transfer)

        let manual = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 132_000_000,
            asOf: day,
            source: .manual
        )
        manual.createdAt = day.addingTimeInterval(15 * 3_600)
        context.insert(manual)
        try context.save()

        let summaries = try service.latestRates()

        #expect(summaries.count == 1)
        #expect(summaries.first?.rate.rateScaled == 132_000_000)
        #expect(summaries.first?.source == .manual)
        #expect(try service.rateBook().rate(from: .usd, to: .kes)?.rateScaled == 132_000_000)
    }

    @Test("A manual rate can be removed by id")
    func deleteRateByID() throws {
        let (service, _) = try makeService()
        let record = try service.addRate(base: .usd, quote: .kes, decimalRate: 130)

        try service.deleteRate(id: record.id)

        #expect(try service.latestRates().isEmpty)
    }

    @Test("A manual rate can be removed but a transfer rate cannot")
    func deleteRules() throws {
        let (service, context) = try makeService()

        let manual = try service.addRate(base: .usd, quote: .kes, decimalRate: 130)
        try service.deleteRate(manual)

        #expect(try service.latestRates().isEmpty)

        let fromTransfer = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 100_000_000,
            asOf: Date(),
            source: .transfer
        )
        context.insert(fromTransfer)
        try context.save()

        #expect(throws: ExchangeRateError.transferRate) {
            try service.deleteRate(fromTransfer)
        }
    }

    @Test("A future-dated manual rate is clamped to the start of today")
    func futureRateClamped() throws {
        let (service, _) = try makeService()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 2_000_000)
        let future = now.addingTimeInterval(60 * 60 * 24 * 30)

        let record = try service.addRate(
            base: .usd,
            quote: .kes,
            decimalRate: 130,
            asOf: future,
            calendar: calendar,
            now: now
        )

        #expect(record.asOf == calendar.startOfDay(for: now))
        #expect(try service.latestRates().first?.asOf == calendar.startOfDay(for: now))
    }
}
