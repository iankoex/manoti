//
//  TransactionFilterTests.swift
//  ManotiTests
//

import Foundation
import Testing

@testable import AppModels
@testable import LedgerFeature

@MainActor
@Suite("Transaction filters")
struct TransactionFilterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private var now: Date {
        date(2026, 11, 23, 12)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .now
    }

    private func entry(
        amountMinor: Int64 = 10_000,
        at occurredAt: Date,
        payee: String = "Shop",
        note: String = "",
        account: Account? = nil
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: amountMinor,
            currencyCode: "KES",
            occurredAt: occurredAt,
            payee: payee,
            note: note
        )
        entry.account = account
        return entry
    }

    private func filtered(
        _ entries: [LedgerEntry],
        filter: TransactionFilter = TransactionFilter(),
        search: String = ""
    ) -> [LedgerEntry] {
        TransactionFilterEngine.apply(
            entries,
            filter: filter,
            searchText: search,
            displayCurrency: CurrencyCatalog.currency(for: "KES"),
            rateBook: nil,
            now: now,
            calendar: calendar
        )
    }

    private func tag(_ name: String, colorHex: String = "#27AE60") -> AppModels.Tag {
        AppModels.Tag(name: name, colorHex: colorHex, symbolName: "tag")
    }

    private func attach(_ tags: [AppModels.Tag], category: SpendingCategory? = nil, to entry: LedgerEntry) {
        let line = LedgerEntryLine(amountMinor: entry.amountMinor, category: category, tags: tags)
        line.entry = entry
        entry.lines = [line]
    }

    @Test("A tag filter keeps entries carrying any selected tag")
    func tagFilter() {
        let nakuru = tag("Nakuru")
        let personal = tag("Personal")
        let tagged = entry(at: date(2026, 11, 23, 8))
        let other = entry(at: date(2026, 11, 23, 9))
        let plain = entry(at: date(2026, 11, 23, 10))
        attach([nakuru], to: tagged)
        attach([personal], to: other)

        var filter = TransactionFilter()
        filter.tagIDs = [nakuru.id]

        let result = filtered([tagged, other, plain], filter: filter)
        #expect(result.map(\.id) == [tagged.id])
        #expect(filtered([tagged, other, plain], filter: TransactionFilter()).count == 3)
    }

    @Test("Search matches a tag name and a split line category")
    func searchLinesAndTags() {
        let nakuru = tag("Nakuru assignment")
        let groceries = SpendingCategory(name: "Groceries", symbolName: "cart", colorHex: "#27AE60")
        let split = entry(at: date(2026, 11, 23, 8), payee: "Supermarket")
        let line = LedgerEntryLine(amountMinor: 5_000, category: groceries, tags: [nakuru])
        line.entry = split
        split.lines = [line]
        let plain = entry(at: date(2026, 11, 23, 9), payee: "Cafe")

        #expect(filtered([split, plain], search: "nakuru").map(\.id) == [split.id])
        #expect(filtered([split, plain], search: "groceries").map(\.id) == [split.id])
    }

    @Test("Today keeps only today's entries")
    func today() {
        let entries = [
            entry(at: date(2026, 11, 23, 8)),
            entry(at: date(2026, 11, 22, 8)),
        ]
        var filter = TransactionFilter()
        filter.datePreset = .today

        #expect(filtered(entries, filter: filter).count == 1)
    }

    @Test("Last 7 days includes the seventh day and nothing older")
    func lastSevenDays() {
        let entries = [
            entry(at: date(2026, 11, 23, 8)),
            entry(at: date(2026, 11, 17, 8)),
            entry(at: date(2026, 11, 16, 8)),
        ]
        var filter = TransactionFilter()
        filter.datePreset = .last7

        #expect(filtered(entries, filter: filter).count == 2)
    }

    @Test("Last month keeps only the previous calendar month")
    func lastMonth() {
        let entries = [
            entry(at: date(2026, 11, 1, 8)),
            entry(at: date(2026, 10, 15, 8)),
        ]
        var filter = TransactionFilter()
        filter.datePreset = .lastMonth

        #expect(filtered(entries, filter: filter).count == 1)
    }

    @Test("A custom between range includes both end days")
    func customBetween() {
        let entries = [
            entry(at: date(2026, 11, 1, 8)),
            entry(at: date(2026, 11, 5, 8)),
            entry(at: date(2026, 11, 10, 20)),
            entry(at: date(2026, 11, 11, 8)),
        ]
        var filter = TransactionFilter()
        filter.datePreset = .custom
        filter.dateMode = .between
        filter.customFrom = date(2026, 11, 1)
        filter.customTo = date(2026, 11, 10)

        #expect(filtered(entries, filter: filter).count == 3)
    }

    @Test("Before and after are open-ended")
    func customBeforeAndAfter() {
        let entries = [
            entry(at: date(2026, 11, 19, 8)),
            entry(at: date(2026, 11, 20, 8)),
            entry(at: date(2026, 11, 21, 8)),
        ]

        var before = TransactionFilter()
        before.datePreset = .custom
        before.dateMode = .before
        before.customFrom = date(2026, 11, 20)
        #expect(filtered(entries, filter: before).count == 1)

        var after = TransactionFilter()
        after.datePreset = .custom
        after.dateMode = .after
        after.customFrom = date(2026, 11, 20)
        #expect(filtered(entries, filter: after).count == 1)
    }

    @Test("Account type keeps only matching accounts")
    func accountKinds() {
        let bank = Account(name: "Bank", kind: .bank)
        let wallet = Account(name: "Wallet", kind: .mobileMoney)

        let entries = [
            entry(at: now, account: bank),
            entry(at: now, account: wallet),
            entry(at: now, account: nil),
        ]

        var filter = TransactionFilter()
        filter.accountKinds = [.bank]

        #expect(filtered(entries, filter: filter).count == 1)
    }

    @Test("Specific accounts can be selected on their own")
    func specificAccounts() {
        let bank = Account(name: "Bank", kind: .bank)
        let wallet = Account(name: "Wallet", kind: .mobileMoney)

        let entries = [
            entry(at: now, account: bank),
            entry(at: now, account: wallet),
        ]

        var filter = TransactionFilter()
        filter.accountIDs = [wallet.id]

        let result = filtered(entries, filter: filter)
        #expect(result.count == 1)
        #expect(result.first?.account?.id == wallet.id)
    }

    @Test("Every type is on by default, including entries without an account")
    func defaultShowsEverything() {
        let bank = Account(name: "Bank", kind: .bank)
        let wallet = Account(name: "Wallet", kind: .mobileMoney)

        let entries = [
            entry(at: now, account: bank),
            entry(at: now, account: wallet),
            entry(at: now, account: nil),
        ]

        #expect(filtered(entries).count == 3)
    }

    @Test("A chosen account is ignored when its type is turned off")
    func accountsAreNarrowedByTypes() {
        let bank = Account(name: "Bank", kind: .bank)
        let wallet = Account(name: "Wallet", kind: .mobileMoney)
        let cash = Account(name: "Cash", kind: .cash)

        let entries = [
            entry(at: now, account: bank),
            entry(at: now, account: wallet),
            entry(at: now, account: cash),
            entry(at: now, account: nil),
        ]

        var filter = TransactionFilter()
        filter.accountKinds = [.bank]
        filter.accountIDs = [wallet.id]

        // The wallet's type is off and the bank account is not chosen.
        #expect(filtered(entries, filter: filter).isEmpty)
    }

    @Test("Turning every type off shows nothing")
    func noTypesShowsNothing() {
        let bank = Account(name: "Bank", kind: .bank)
        let entries = [entry(at: now, account: bank), entry(at: now, account: nil)]

        var filter = TransactionFilter()
        filter.accountKinds = []

        #expect(filtered(entries, filter: filter).isEmpty)
    }

    @Test("A reversed amount range still works")
    func amountBounds() {
        let entries = [
            entry(amountMinor: 10_000, at: now),
            entry(amountMinor: 50_000, at: now),
            entry(amountMinor: 200_000, at: now),
        ]

        var filter = TransactionFilter()
        filter.minimumAmountText = "1,000"
        filter.maximumAmountText = "500"

        let result = filtered(entries, filter: filter)
        #expect(result.map(\.amountMinor) == [50_000])
    }

    @Test("Search matches payee, note and account name")
    func search() {
        let wallet = Account(name: "Wallet", kind: .mobileMoney)
        let entries = [
            entry(at: now, payee: "KPLC PREPAID"),
            entry(at: now, payee: "Shell", note: "fuel top up"),
            entry(at: now, payee: "Unknown", account: wallet),
        ]

        #expect(filtered(entries, search: "kplc").count == 1)
        #expect(filtered(entries, search: "fuel").count == 1)
        #expect(filtered(entries, search: "wallet").count == 1)
        #expect(filtered(entries, search: "nothing").isEmpty)
    }
}
