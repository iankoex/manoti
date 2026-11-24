//
//  SharedRulesTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppPackageExtensions
@testable import AppServices

@MainActor
@Suite("Shared rules")
struct SharedRulesTests {
    private let deposit =
        "Dear Customer, your cash deposit transaction of KES 2,900.00 by 012*******0123 to AC/NO IAN KIPRONO (16-11-2026 at 17:36:02) on LSK126320012 was successful. CDM Ref . Thank you. For Enquiry, contact us on 0719 088 000 or 0732 100 000. I&M Bank Ltd.On Your Side."

    private static let document = #"""
        {
          "version": 1,
          "updatedAt": "2026-11-23T00:00:00Z",
          "rules": [
            {
              "key": "bank-cash-deposit",
              "name": "Cash deposit",
              "type": "income",
              "pattern": "CASH DEPOSIT TRANSACTION OF\\s+(?<amount>(?:KSH|KES|KSHS)\\s?[\\d,]+(?:\\.\\d{1,2})?)\\s+(?:BY\\s+[0-9*]+\\s+)?TO\\s+AC/NO\\s+(?<payee>.+?)\\s+\\((?<date>\\d{1,2}-\\d{1,2}-\\d{4})\\s+AT\\s+(?<time>\\d{1,2}:\\d{2}:\\d{2})\\)\\s+ON\\s+(?<ref>[A-Z0-9]+)\\s+WAS SUCCESSFUL",
              "fieldPatterns": {},
              "sample": "Dear Customer, your cash deposit transaction of KES 2,900.00 by 012*******0123 to AC/NO IAN KIPRONO (16-11-2026 at 17:36:02) on LSK126320012 was successful."
            }
          ]
        }
        """#

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return context
    }

    @Test("The bundled rule file installs")
    func repositoryFile() throws {
        let context = try makeContext()
        let data = try SharedRulesService.bundledData()

        let result = try SharedRulesService(context: context).install(data)
        #expect(result.ruleCount >= 1)
    }

    @Test("The bundled rules install once, then stay put")
    func bundledInstallsOnce() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "SharedRulesTests.\(UUID().uuidString)")!
        let service = SharedRulesService(context: context, defaults: defaults)

        let first = try service.installBundledRulesIfNeeded()
        #expect(first?.ruleCount == 3)

        let second = try service.installBundledRulesIfNeeded()
        #expect(second == nil)
        #expect(try context.fetchCount(FetchDescriptor<ParseRuleSet>()) == 3)
    }

    @Test("A first install is quiet; an app update notifies")
    func notifiesOnlyOnAppUpdate() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "SharedRulesTests.\(UUID().uuidString)")!
        let service = SharedRulesService(context: context, defaults: defaults)

        let first = try service.installBundledRulesIfNeeded()
        #expect(first?.shouldNotify == false)

        // Simulate the next app update: a previous revision exists and the bundle moves on.
        defaults.set(0, forKey: SharedRulesService.revisionKey)

        let second = try service.installBundledRulesIfNeeded()
        #expect(second?.shouldNotify == true)
    }

    @Test("A newer installed revision is not overwritten by an older bundle")
    func bundledDoesNotDowngrade() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "SharedRulesTests.\(UUID().uuidString)")!
        let service = SharedRulesService(context: context, defaults: defaults)

        let newer = Self.document.replacingOccurrences(
            of: #""version": 1"#,
            with: #""version": 1, "revision": 99"#
        )
        _ = try service.install(Data(newer.utf8))

        let bundled = try service.installBundledRulesIfNeeded()

        #expect(bundled == nil)
        #expect(defaults.integer(forKey: SharedRulesService.revisionKey) == 99)
    }

    @Test("A deleted shared set is restored from the bundle")
    func bundledRestoresDeletedSet() throws {
        let context = try makeContext()
        let defaults = UserDefaults(suiteName: "SharedRulesTests.\(UUID().uuidString)")!
        let service = SharedRulesService(context: context, defaults: defaults)

        _ = try service.installBundledRulesIfNeeded()

        let sets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let shared = try #require(sets.first { $0.seedKey == SharedRulesService.ruleSetSeedKey })
        context.delete(shared)
        try context.save()

        let restored = try service.installBundledRulesIfNeeded()

        #expect(restored?.ruleCount == 3)
    }

    @Test("A rule already covered by a user set is skipped, not duplicated")
    func userDuplicateIsSkipped() throws {
        let context = try makeContext()
        let document = try JSONDecoder().decode(
            SharedRuleDocument.self,
            from: SharedRulesService.bundledData()
        )
        let deposit = try #require(document.rules.first { $0.key == "bank-cash-deposit" })

        let mine = ParseRuleSet(name: "My rules", senderMatchers: "*", priority: 97)
        context.insert(mine)
        let rule = ParseRule(
            name: "My deposit",
            messageType: .income,
            pattern: deposit.pattern
        )
        rule.ruleSet = mine
        context.insert(rule)
        try context.save()

        let result = try SharedRulesService(context: context).install(
            SharedRulesService.bundledData()
        )

        #expect(result.ruleCount == 2)
        #expect(result.skippedCount == 1)
    }

    @Test("The bundled rules read an M-Pesa paybill message")
    func repositoryFileReadsPaybill() throws {
        let context = try makeContext()
        _ = try SharedRulesService(context: context).install(SharedRulesService.bundledData())

        let text =
            "UKN6H2LLXH Confirmed. Ksh100.00 sent to KPLC PREPAID for account 22213031655 on 23/11/26 at 8:10 PM New M-PESA balance is Ksh1,275.68. Transaction cost, Ksh0.00.Amount you can transact within the day is 497,620.00. See all your balances now https://saf.cx/kWQpy"

        let outcome = try ParserService(context: context).parse(
            text: text,
            sender: nil,
            receivedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        guard case .parsed(let message) = outcome else {
            Issue.record("The paybill message was not recognised")
            return
        }

        #expect(message.messageType == .expense)
        #expect(message.amountMinor == 10_000)
        #expect(message.payee == "KPLC PREPAID")
        #expect(message.reference == "UKN6H2LLXH")
        #expect(message.feeMinor == 0)
        #expect(message.balanceAfterMinor == 127_568)
        #expect(message.dateFromMessage)

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: message.occurredAt
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 23)
        #expect(parts.hour == 20)
        #expect(parts.minute == 10)
    }

    @Test("The bundled rules read an M-Pesa send-to-person message")
    func repositoryFileReadsSentToPerson() throws {
        let context = try makeContext()
        _ = try SharedRulesService(context: context).install(SharedRulesService.bundledData())

        let text =
            "UKN6H2LQAK Confirmed. Ksh200.00 sent to JANET  MORANG'A 0798734779 on 23/11/26 at 8:16 PM. New M-PESA balance is Ksh1,068.68. Transaction cost, Ksh7.00.  Amount you can transact within the day is 497,420.00. See all your balances now https://saf.cx/iqIzU"

        let outcome = try ParserService(context: context).parse(
            text: text,
            sender: nil,
            receivedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        guard case .parsed(let message) = outcome else {
            Issue.record("The send-to-person message was not recognised")
            return
        }

        #expect(message.messageType == .expense)
        #expect(message.amountMinor == 20_000)
        #expect(message.payee == "JANET MORANG'A 0798734779")
        #expect(message.reference == "UKN6H2LQAK")
        #expect(message.feeMinor == 700)
        #expect(message.balanceAfterMinor == 106_868)
        #expect(message.dateFromMessage)

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: message.occurredAt
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 23)
        #expect(parts.hour == 20)
        #expect(parts.minute == 16)
    }

    @Test("A downloaded rule parses a cash deposit as income")
    func depositRule() throws {
        let context = try makeContext()
        let result = try SharedRulesService(context: context).install(Data(Self.document.utf8))

        #expect(result.ruleCount == 1)
        #expect(result.ruleSetName == SharedRulesService.ruleSetName)

        let outcome = try ParserService(context: context).parse(
            text: deposit,
            sender: nil,
            receivedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )

        guard case .parsed(let message) = outcome else {
            Issue.record("The deposit message was not recognised")
            return
        }

        #expect(message.messageType == .income)
        #expect(message.amountMinor == 290_000)
        #expect(message.payee == "IAN KIPRONO")
        #expect(message.reference == "LSK126320012")
        #expect(message.dateFromMessage)

        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: message.occurredAt
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 16)
        #expect(parts.hour == 17)
        #expect(parts.minute == 36)
        #expect(parts.second == 2)
    }

    @Test("Updating replaces the downloaded rules and leaves the seeded rules alone")
    func updateReplaces() throws {
        let context = try makeContext()
        let service = SharedRulesService(context: context)

        _ = try service.install(Data(Self.document.utf8))
        _ = try service.install(Data(Self.document.utf8))

        let sets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let bank = try #require(sets.first { $0.seedKey == "im-bank" })
        let updates = try #require(sets.first { $0.seedKey == SharedRulesService.ruleSetSeedKey })

        #expect(bank.rules?.count == 4)
        #expect(updates.rules?.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<ParseRuleSet>()) == 3)
    }

    @Test("An invalid pattern is rejected without changing the installed rules")
    func invalidPatternIsRejected() throws {
        let context = try makeContext()
        let service = SharedRulesService(context: context)
        _ = try service.install(Data(Self.document.utf8))

        let before = try context.fetchCount(FetchDescriptor<ParseRule>())
        let broken = Self.document.replacingOccurrences(of: "CASH DEPOSIT", with: "CASH (DEPOSIT")

        #expect(throws: SharedRulesError.invalidPattern("Cash deposit")) {
            _ = try service.install(Data(broken.utf8))
        }

        #expect(try context.fetchCount(FetchDescriptor<ParseRule>()) == before)
    }

    @Test("A newer file version is refused rather than half-read")
    func newerVersionIsRefused() throws {
        let context = try makeContext()
        let newer = Self.document.replacingOccurrences(
            of: #""version": 1"#,
            with: #""version": 99"#
        )

        #expect(throws: SharedRulesError.unsupportedVersion(99)) {
            _ = try SharedRulesService(context: context).install(Data(newer.utf8))
        }
    }

    @Test("A rule without an amount capture is refused")
    func amountCaptureIsRequired() throws {
        let context = try makeContext()
        let noAmount = Self.document.replacingOccurrences(
            of: "(?<amount>",
            with: "(?<total>"
        )

        #expect(throws: SharedRulesError.self) {
            _ = try SharedRulesService(context: context).install(Data(noAmount.utf8))
        }
    }
}
