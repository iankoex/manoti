//
//  ExchangeRateBookTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels

@Suite("ExchangeRateBook")
struct ExchangeRateBookTests {
    private let kes = Currency.kes
    private let usd = Currency.usd

    @Test("The newest record for a pair wins")
    func newestWins() {
        let older = ExchangeRateRecord(
            baseCode: "KES",
            quoteCode: "USD",
            rateScaled: 7_000,
            asOf: Date(timeIntervalSince1970: 100)
        )
        let newer = ExchangeRateRecord(
            baseCode: "KES",
            quoteCode: "USD",
            rateScaled: 7_750,
            asOf: Date(timeIntervalSince1970: 200)
        )

        let book = ExchangeRateBook(records: [older, newer])
        let rate = book.rate(from: kes, to: usd)

        #expect(rate?.rateScaled == 7_750)
    }

    @Test("A reverse pair is inverted")
    func reversePair() {
        let record = ExchangeRateRecord(baseCode: "KES", quoteCode: "USD", rateScaled: 7_750)
        let book = ExchangeRateBook(records: [record])

        let converted = book.convert(Money(minorUnits: 7_750, currency: usd), to: kes)

        #expect(converted != nil)
        #expect(abs((converted?.minorUnits ?? 0) - 1_000_000) <= 1)
    }

    @Test("Same currency converts to itself")
    func sameCurrency() {
        let book = ExchangeRateBook(records: [])
        let money = Money(minorUnits: 1_234, currency: kes)

        #expect(book.convert(money, to: kes) == money)
        #expect(book.convert(money, to: usd) == nil)
    }

    @Test("A later rate does not change an earlier conversion")
    func noRetroactiveRate() {
        let early = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)
        let book = ExchangeRateBook(records: [
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: early),
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 132_000_000, asOf: later),
        ])

        let onEarly = book.convert(Money(minorUnits: 10_000, currency: usd), to: kes, on: early)
        let onLater = book.convert(Money(minorUnits: 10_000, currency: usd), to: kes, on: later)

        #expect(onEarly?.minorUnits == 1_300_000)
        #expect(onLater?.minorUnits == 1_320_000)
    }

    @Test("A date before the first rate has no rate")
    func beforeFirstRate() {
        let firstRateDay = Date(timeIntervalSince1970: 1_000_000)
        let earlier = Date(timeIntervalSince1970: 500_000)
        let book = ExchangeRateBook(records: [
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: firstRateDay)
        ])

        #expect(book.rate(from: usd, to: kes, on: earlier) == nil)
        #expect(book.convert(Money(minorUnits: 10_000, currency: usd), to: kes, on: earlier) == nil)
    }

    @Test("A later-created same-day manual rate beats an earlier transfer rate")
    func sameDayManualWins() {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let transfer = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 130_000_000,
            asOf: day.addingTimeInterval(14 * 3_600),
            source: .transfer
        )
        transfer.createdAt = day.addingTimeInterval(8 * 3_600)

        let manual = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 132_000_000,
            asOf: day,
            source: .manual
        )
        manual.createdAt = day.addingTimeInterval(15 * 3_600)

        let book = ExchangeRateBook(records: [transfer, manual])

        #expect(book.rate(from: .usd, to: .kes)?.rateScaled == 132_000_000)
        #expect(book.rate(from: .usd, to: .kes, on: day)?.rateScaled == 132_000_000)
    }

    @Test("A historical reverse pair is inverted")
    func historicalInverse() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let book = ExchangeRateBook(records: [
            ExchangeRateRecord(baseCode: "USD", quoteCode: "KES", rateScaled: 130_000_000, asOf: date)
        ])

        let converted = book.convert(Money(minorUnits: 1_300_000, currency: kes), to: usd, on: date)

        #expect(converted?.minorUnits == 10_000)
    }

    @Test("Same currency converts to itself on any date")
    func sameCurrencyOnDate() {
        let book = ExchangeRateBook(records: [])
        let money = Money(minorUnits: 1_234, currency: kes)

        #expect(book.convert(money, to: kes, on: Date(timeIntervalSince1970: 1)) == money)
    }

    @Test("A newer inverse record beats an older direct record")
    func newerInverseBeatsOlderDirect() throws {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        let direct = ExchangeRateRecord(
            baseCode: "KES",
            quoteCode: "USD",
            rateScaled: 7_000,
            asOf: older
        )
        let inverse = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 130_000_000,
            asOf: newer
        )

        let book = ExchangeRateBook(records: [direct, inverse])
        let expected = try #require(FXRate(base: usd, quote: kes, rateScaled: 130_000_000)).inverted

        #expect(book.rate(from: kes, to: usd)?.rateScaled == expected.rateScaled)
    }

    @Test("A newer inverse record beats an older direct record on a date")
    func newerInverseBeatsOlderDirectOnDate() throws {
        let older = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        let direct = ExchangeRateRecord(
            baseCode: "KES",
            quoteCode: "USD",
            rateScaled: 7_000,
            asOf: older
        )
        let inverse = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 130_000_000,
            asOf: newer
        )

        let book = ExchangeRateBook(records: [direct, inverse])
        let expected = try #require(FXRate(base: usd, quote: kes, rateScaled: 130_000_000)).inverted

        #expect(book.rate(from: kes, to: usd, on: newer)?.rateScaled == expected.rateScaled)
        #expect(book.rate(from: kes, to: usd, on: older)?.rateScaled == 7_000)
    }

    @Test("A rate captured later in the day applies to a morning entry")
    func sameDayTimeOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let rateTime = try #require(calendar.date(byAdding: .hour, value: 14, to: dayStart))
        let morning = try #require(calendar.date(byAdding: .hour, value: 9, to: dayStart))

        let book = ExchangeRateBook(
            records: [
                ExchangeRateRecord(
                    baseCode: "USD",
                    quoteCode: "KES",
                    rateScaled: 130_000_000,
                    asOf: rateTime,
                    source: .transfer
                )
            ],
            calendar: calendar
        )

        #expect(book.rate(from: usd, to: kes, on: morning)?.rateScaled == 130_000_000)
        #expect(book.convert(Money(minorUnits: 10_000, currency: usd), to: kes, on: morning)?.minorUnits == 1_300_000)
    }

    @Test("Equal dates fall back to createdAt, then id")
    func deterministicTieBreak() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let low = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 100_000_000,
            asOf: date
        )
        let high = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 130_000_000,
            asOf: date
        )

        low.createdAt = date
        high.createdAt = date
        low.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        high.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF") ?? UUID()

        let book = ExchangeRateBook(records: [high, low])

        #expect(book.rate(from: usd, to: kes)?.rateScaled == 130_000_000)
    }
}
