//
//  ReconciliationServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("ReconciliationService")
struct ReconciliationServiceTests {
    private let paid =
        "UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Nixomb Limited - Shell Bellevue. on 21/11/26 at 11:54 AM.New M-PESA balance is Ksh939.68. Transaction cost, Ksh8.30."
    private let received =
        "UKJME2X5ZR Confirmed.You have received Ksh100.00 from BRENDAH  MBINYA 0746***702 on 19/11/26 at 3:07 PM  New M-PESA balance is Ksh1,744.98."
    private let card =
        "Dear IAN, You made a purchase ofKES 766.00 on 2026-11-19 17:42:06 at QUICK MART LIMITED using I&M 7653********7653."

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeDate(day: Int, hour: Int = 12, minute: Int = 0) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }

    private func makeServices() throws -> (ReconciliationService, AccountService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return (
            ReconciliationService(context: context, calendar: calendar),
            AccountService(context: context),
            context
        )
    }

    @discardableResult
    private func addEntry(
        _ kind: LedgerEntryKind = .expense,
        amountMinor: Int64,
        feeMinor: Int64 = 0,
        account: Account?,
        occurredAt: Date,
        externalRef: String = "",
        status: LedgerEntryStatus = .confirmed,
        isSoftDeleted: Bool = false,
        in context: ModelContext
    ) -> LedgerEntry {
        let entry = LedgerEntry(
            kind: kind,
            amountMinor: amountMinor,
            feeMinor: feeMinor,
            currencyCode: account?.currencyCode ?? "KES",
            occurredAt: occurredAt
        )
        entry.account = account
        entry.externalRef = externalRef
        entry.status = status
        entry.isSoftDeleted = isSoftDeleted
        context.insert(entry)
        return entry
    }

    @Test("A repeated token reuses its open session")
    func sessionReuseByToken() throws {
        let (service, _, context) = try makeServices()
        let start = try makeDate(day: 18, hour: 0)
        let end = try makeDate(day: 21, hour: 0)

        let first = try service.startSession(token: "day-1", periodStart: start, periodEnd: end)
        let second = try service.startSession(token: "day-1", periodStart: start, periodEnd: end)
        let latest = try service.startSession(token: nil, periodStart: start, periodEnd: end)

        #expect(first.id == second.id)
        #expect(first.id == latest.id)
        #expect(first.periodStart == start)
        #expect(first.periodEnd == end)
        #expect(try context.fetchCount(FetchDescriptor<ReconcileSession>()) == 1)
        #expect(try service.latestSession()?.id == first.id)
    }

    @Test("Collecting parses a seeded M-Pesa message")
    func collectParsesMessage() throws {
        let (service, _, context) = try makeServices()
        let receivedAt = try makeDate(day: 21, hour: 12)

        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: receivedAt,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )

        #expect(message.amountMinor == 151_000)
        #expect(message.feeMinor == 830)
        #expect(message.reference == "UKL6H2AF65")
        #expect(message.parsedKind == .expense)
        #expect(message.dateFromMessage)
        #expect(message.classification == .pending)
        #expect(message.session?.messages?.count == 1)

        let duplicate = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: receivedAt,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )

        #expect(duplicate.id == message.id)
        #expect(message.session?.messageCount == 1)
        #expect(try context.fetchCount(FetchDescriptor<ReconcileMessage>()) == 1)
    }

    @Test("An exact reference matches even when the amount and time differ")
    func exactReferenceMatch() throws {
        let (service, accounts, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let receivedAt = try makeDate(day: 21, hour: 12)

        let entry = addEntry(
            amountMinor: 151_000,
            account: mobile,
            occurredAt: try makeDate(day: 5, hour: 8),
            externalRef: "UKL6H2AF65",
            in: context
        )

        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: receivedAt,
            token: nil,
            periodStart: try makeDate(day: 1, hour: 0),
            periodEnd: try makeDate(day: 30, hour: 0)
        )
        let summary = try service.finalise(try #require(message.session))

        #expect(message.classification == .matched)
        #expect(message.matchedEntryID == entry.id)
        #expect(summary.matchedCount == 1)
        #expect(summary.messageOnlyCount == 0)
    }

    @Test("Amount within 1% and ten minutes on the same account matches")
    func amountAndTimeMatch() throws {
        let (service, accounts, context) = try makeServices()
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)

        let receivedAt = try makeDate(day: 19, hour: 12)
        let entry = addEntry(
            amountMinor: 76_300,
            account: cardAccount,
            occurredAt: receivedAt.addingTimeInterval(5 * 60),
            in: context
        )

        let message = try service.collect(
            text: card,
            sender: "IM BANK",
            receivedAt: receivedAt,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )
        let summary = try service.finalise(try #require(message.session))

        #expect(message.accountHint == "7653")
        #expect(message.classification == .matched)
        #expect(message.matchedEntryID == entry.id)
        #expect(summary.matchedCount == 1)
        #expect(summary.possibleCount == 0)
    }

    @Test("An exact same-day amount is possible, not matched")
    func sameDayExactAmountIsPossible() throws {
        let (service, accounts, context) = try makeServices()
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)

        let receivedAt = try makeDate(day: 19, hour: 10)
        let entry = addEntry(
            amountMinor: 76_600,
            account: cardAccount,
            occurredAt: receivedAt.addingTimeInterval(2 * 60 * 60),
            in: context
        )

        let message = try service.collect(
            text: card,
            sender: "IM BANK",
            receivedAt: receivedAt,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )
        let summary = try service.finalise(try #require(message.session))

        #expect(message.classification == .possible)
        #expect(message.matchedEntryID == nil)
        #expect(summary.matchedCount == 0)
        #expect(summary.possibleCount == 1)
        #expect(summary.appOnlyCount == 1)
        let appOnlyIDs = try service.appOnlyEntries(in: try #require(message.session)).map(\.id)
        #expect(appOnlyIDs == [entry.id])
    }

    @Test("A message without a received time skips time matching and is counted")
    func missingReceivedAtSkipsTimeMatching() throws {
        let (service, accounts, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: nil,
            token: nil,
            periodStart: Date().addingTimeInterval(-86_400),
            periodEnd: Date().addingTimeInterval(86_400)
        )

        addEntry(
            amountMinor: 151_000,
            feeMinor: 830,
            account: mobile,
            occurredAt: Date(),
            in: context
        )

        let summary = try service.finalise(try #require(message.session))

        #expect(message.classification == .missing)
        #expect(message.receivedAt == nil)
        #expect(summary.missingTimeCount == 1)
        #expect(summary.matchedCount == 0)
    }

    @Test("Messages never match entries on a different account")
    func differentAccountsDoNotMatch() throws {
        let (service, accounts, context) = try makeServices()
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let receivedAt = try makeDate(day: 19, hour: 12)
        let entry = addEntry(
            amountMinor: 76_600,
            account: mobile,
            occurredAt: receivedAt,
            in: context
        )

        let message = try service.collect(
            text: card,
            sender: "IM BANK",
            receivedAt: receivedAt,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )
        try service.finalise(try #require(message.session))

        #expect(message.classification == .missing)
        #expect(message.matchedEntryID == nil)
        #expect(try service.appOnlyEntries(in: try #require(message.session)).map(\.id) == [entry.id])
    }

    @Test("The app-only bucket excludes matched and ignored rows")
    func appOnlyBucketAndIgnorePersistence() throws {
        let (service, accounts, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let time = try makeDate(day: 21, hour: 12)

        let matched = addEntry(
            amountMinor: 151_000,
            account: mobile,
            occurredAt: time,
            externalRef: "UKL6H2AF65",
            in: context
        )
        let ignored = addEntry(
            amountMinor: 2_500,
            account: mobile,
            occurredAt: time.addingTimeInterval(-60),
            in: context
        )
        let extra = addEntry(
            amountMinor: 7_500,
            account: mobile,
            occurredAt: time.addingTimeInterval(-120),
            in: context
        )
        addEntry(
            .openingBalance,
            amountMinor: 1_000_000,
            account: mobile,
            occurredAt: time.addingTimeInterval(-300),
            in: context
        )

        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: time,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 22, hour: 0)
        )
        let session = try #require(message.session)

        try service.ignore(appEntry: ignored, in: session)
        #expect(session.ignoredEntryIDs.contains(ignored.id))

        let summary = try service.finalise(session)

        #expect(summary.appOnlyCount == 1)
        #expect(try service.appOnlyEntries(in: session).map(\.id) == [extra.id])
        #expect(!(try service.appOnlyEntries(in: session).contains { $0.id == matched.id }))
        #expect(!(try service.appOnlyEntries(in: session).contains { $0.id == ignored.id }))

        try service.unignore(appEntry: ignored, in: session)
        #expect(try Set(service.appOnlyEntries(in: session).map(\.id)) == [ignored.id, extra.id])

        try service.ignore(appEntry: ignored, in: session)
        #expect(throws: ReconcileError.sessionFinalised) {
            try service.finalise(session)
        }
        #expect(!(try service.appOnlyEntries(in: session).contains { $0.id == ignored.id }))
    }

    @Test("Importing a missing message creates one needsReview row and is idempotent")
    func importMessageIsIdempotent() throws {
        let (service, accounts, context) = try makeServices()
        _ = try accounts.create(name: "M-Pesa", kind: .mobileMoney)

        let time = try makeDate(day: 21, hour: 12)
        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: time,
            token: nil,
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )
        try service.finalise(try #require(message.session))
        #expect(message.classification == .missing)

        let before = try context.fetchCount(FetchDescriptor<LedgerEntry>())
        let entry = try service.importMessage(message)

        #expect(entry.kind == .expense)
        #expect(entry.amountMinor == 151_000)
        #expect(entry.feeMinor == 830)
        #expect(entry.status == .needsReview)
        #expect(entry.source == .reconcile)
        #expect(entry.account == nil)
        #expect(entry.externalRef == "UKL6H2AF65")
        #expect(entry.rawMessage == paid)
        #expect(entry.messageSender == "M-PESA")
        #expect(entry.note == "Imported from reconciliation")
        #expect(message.classification == .imported)
        #expect(message.matchedEntryID == entry.id)
        #expect(!entry.dedupeHash.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == before + 1)

        let refreshed = try service.summary(for: try #require(message.session))
        #expect(refreshed.messageOnlyCount == 0)

        let again = try service.importMessage(message)
        #expect(again.id == entry.id)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == before + 1)
    }

    @Test("Importing a possible duplicate never double-books the balance")
    func possibleImportDoesNotDoubleBook() throws {
        let (service, accounts, context) = try makeServices()
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)

        let time = try makeDate(day: 19, hour: 17, minute: 42)
        _ = addEntry(
            amountMinor: 76_600,
            account: cardAccount,
            occurredAt: try makeDate(day: 19, hour: 14),
            in: context
        )

        let session = try service.startSession(
            token: "possible",
            periodStart: try makeDate(day: 19, hour: 0),
            periodEnd: try makeDate(day: 20, hour: 0)
        )
        let message = try service.collect(
            text: card,
            sender: "IM BANK",
            receivedAt: time,
            token: "possible",
            periodStart: session.periodStart,
            periodEnd: session.periodEnd
        )
        _ = try service.finalise(session)
        #expect(message.classification == .possible)

        let before = cardAccount.balance.minorUnits
        let entry = try service.importMessage(message)

        #expect(entry.account == nil)
        #expect(cardAccount.balance.minorUnits == before)
        #expect(!entry.dedupeHash.isEmpty)
    }

    @Test("A constant session token starts a fresh run after the batch window")
    func sessionExpires() throws {
        let (service, _, context) = try makeServices()
        let first = try service.startSession(
            token: "daily",
            periodStart: try makeDate(day: 21, hour: 0),
            periodEnd: try makeDate(day: 22, hour: 0)
        )
        first.startedAt = Date().addingTimeInterval(-3_600)
        try context.save()

        let second = try service.startSession(
            token: "daily",
            periodStart: try makeDate(day: 22, hour: 0),
            periodEnd: try makeDate(day: 23, hour: 0)
        )
        #expect(second.id != first.id)
    }

    @Test("A transfer leg is not imported as a single row")
    func transferImportIsRefused() throws {
        let (service, accounts, _) = try makeServices()
        let bank = try accounts.create(name: "IM Bank", kind: .bank)
        try accounts.addIdentifier(value: "IM BANK", type: .sender, to: bank)

        let session = try service.startSession(
            token: "transfer",
            periodStart: try makeDate(day: 21, hour: 0),
            periodEnd: try makeDate(day: 22, hour: 0)
        )
        let message = try service.collect(
            text:
                "Bank to M-PESA transfer of KES 600.00 to 254700000000 - IAN KIPRONO successfully processed. Transaction Ref ID: 5951WTXH3777. M-PESA Ref ID: UKK6H292PF.",
            sender: "IM BANK",
            receivedAt: try makeDate(day: 21, hour: 12),
            token: "transfer",
            periodStart: session.periodStart,
            periodEnd: session.periodEnd
        )
        _ = try service.finalise(session)

        #expect(throws: ReconcileError.transferNeedsPairing) {
            try service.importMessage(message)
        }
    }

    @Test("Summary counts and display text describe every bucket")
    func summaryCountsAndDisplayText() throws {
        let (service, accounts, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)

        let time = try makeDate(day: 19, hour: 12)
        _ = addEntry(
            amountMinor: 151_000,
            account: mobile,
            occurredAt: time,
            externalRef: "UKL6H2AF65",
            in: context
        )
        let possibleEntry = addEntry(
            amountMinor: 76_600,
            account: cardAccount,
            occurredAt: time.addingTimeInterval(2 * 60 * 60),
            in: context
        )
        let appOnly = addEntry(
            amountMinor: 4_200,
            account: mobile,
            occurredAt: time.addingTimeInterval(-60),
            in: context
        )
        let ignored = addEntry(
            amountMinor: 1_000,
            account: mobile,
            occurredAt: time.addingTimeInterval(-120),
            in: context
        )

        let session = try service.startSession(
            token: "summary",
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 22, hour: 0)
        )
        try service.ignore(appEntry: ignored, in: session)

        _ = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: time,
            token: "summary",
            periodStart: session.periodStart,
            periodEnd: session.periodEnd
        )
        _ = try service.collect(
            text: card,
            sender: "IM BANK",
            receivedAt: time,
            token: "summary",
            periodStart: session.periodStart,
            periodEnd: session.periodEnd
        )
        _ = try service.collect(
            text: received,
            sender: "M-PESA",
            receivedAt: time,
            token: "summary",
            periodStart: session.periodStart,
            periodEnd: session.periodEnd
        )

        let summary = try service.finalise(session)

        #expect(summary.messageCount == 3)
        #expect(summary.matchedCount == 1)
        #expect(summary.possibleCount == 1)
        #expect(summary.messageOnlyCount == 1)
        #expect(summary.appOnlyCount == 2)
        #expect(summary.ignoredCount == 1)
        #expect(summary.missingTimeCount == 0)
        #expect(
            summary.displayText
                == "3 messages · 1 matched · 1 missing from app · 2 not in messages · 1 possible · 1 ignored"
        )
        #expect(try service.appOnlyEntries(in: session).map(\.id) == [possibleEntry.id, appOnly.id])
    }

    @Test("A message received after midnight still matches its own dated entry")
    func sessionExpandsAcrossMidnight() throws {
        let (service, accounts, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let receivedAt = try makeDate(day: 22, hour: 0, minute: 5)

        let session = try service.startSession(
            token: "midnight",
            periodStart: try makeDate(day: 22, hour: 0),
            periodEnd: try makeDate(day: 23, hour: 0)
        )
        let entry = addEntry(
            amountMinor: 151_000,
            account: mobile,
            occurredAt: try makeDate(day: 21, hour: 11, minute: 54),
            externalRef: "UKL6H2AF65",
            in: context
        )

        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: receivedAt,
            token: "midnight",
            periodStart: session.periodStart,
            periodEnd: session.periodEnd
        )
        let expanded = try #require(message.session)

        #expect(expanded.periodStart == (try makeDate(day: 21, hour: 0)))
        #expect(expanded.periodEnd == (try makeDate(day: 23, hour: 0)))

        let summary = try service.finalise(expanded)
        #expect(message.classification == .matched)
        #expect(message.matchedEntryID == entry.id)
        #expect(summary.matchedCount == 1)
    }

    @Test("A finalised session returns the same summary when read again")
    func summaryIsRepeatable() throws {
        let (service, accounts, context) = try makeServices()
        let cardAccount = try accounts.create(name: "I&M Card", kind: .card)
        try accounts.addIdentifier(value: "7653", type: .cardLast4, to: cardAccount)

        let receivedAt = try makeDate(day: 19, hour: 12)
        addEntry(
            amountMinor: 76_300,
            account: cardAccount,
            occurredAt: receivedAt.addingTimeInterval(5 * 60),
            in: context
        )

        let message = try service.collect(
            text: card,
            sender: "IM BANK",
            receivedAt: receivedAt,
            token: "repeat",
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )
        let session = try #require(message.session)

        let first = try service.finalise(session)
        let second = try service.summary(for: session)

        #expect(first.displayText == second.displayText)
        #expect(first.matchedCount == second.matchedCount)
        #expect(second.messageCount == 1)
    }

    @Test("A classification preview does not finalise the session")
    func classificationPreview() throws {
        let (service, accounts, context) = try makeServices()
        let mobile = try accounts.create(name: "M-Pesa", kind: .mobileMoney)
        let receivedAt = try makeDate(day: 21, hour: 12)

        addEntry(
            amountMinor: 151_000,
            account: mobile,
            occurredAt: try makeDate(day: 5, hour: 8),
            externalRef: "UKL6H2AF65",
            in: context
        )

        let message = try service.collect(
            text: paid,
            sender: "M-PESA",
            receivedAt: receivedAt,
            token: "preview",
            periodStart: try makeDate(day: 1, hour: 0),
            periodEnd: try makeDate(day: 30, hour: 0)
        )
        let session = try #require(message.session)

        #expect(try service.classificationPreview(for: message, in: session) == .matched)
        #expect(!session.isFinalised)

        _ = try service.finalise(session)
        #expect(message.classification == .matched)
    }

    @Test("Both reconcile models are in the schema and keep their inverse")
    func schemaAndInverse() throws {
        #expect(ManotiSchema.models.count == 27)
        #expect(ManotiSchema.models.contains { $0 == ReconcileSession.self })
        #expect(ManotiSchema.models.contains { $0 == ReconcileMessage.self })

        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let session = ReconcileSession(
            token: "abc",
            periodStart: try makeDate(day: 18, hour: 0),
            periodEnd: try makeDate(day: 21, hour: 0)
        )
        let message = ReconcileMessage(text: paid, sender: "M-PESA", dedupeHash: "hash")
        message.session = session
        context.insert(session)
        context.insert(message)
        try context.save()

        #expect(session.messages?.count == 1)
        #expect(message.session?.id == session.id)
        #expect(session.ignoredEntryIDs.isEmpty)
    }
}
