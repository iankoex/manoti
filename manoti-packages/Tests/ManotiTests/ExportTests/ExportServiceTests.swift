//
//  ExportServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppPackageExtensions
@testable import AppServices

@MainActor
@Suite("ExportService")
struct ExportServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeDate(
        day: Int,
        month: Int = 11,
        year: Int = 2026,
        hour: Int = 12,
        minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    private func makeFreshContext() throws -> ModelContext {
        try makeContext()
    }

    private struct Fixture {
        let context: ModelContext
        let settings: AppSettings
        let group: CategoryGroup
        let category: SpendingCategory
        let account: Account
        let usdAccount: Account
        let identifier: AccountIdentifier
        let memory: MerchantMemory
        let alias: MerchantAlias
        let smartRule: SmartRule
        let ruleSet: ParseRuleSet
        let parseRule: ParseRule
        let expense: LedgerEntry
        let softDeleted: LedgerEntry
        let transfer: Transfer
        let outLeg: LedgerEntry
        let inLeg: LedgerEntry
        let loan: Loan
        let loanEntry: LedgerEntry
        let investment: Investment
        let purchase: InvestmentCashFlow
        let coupon: InvestmentCashFlow
        let investmentEntry: LedgerEntry
        let rate: ExchangeRateRecord
        let period: BudgetPeriod
        let envelope: Envelope
        let alert: BudgetAlert
        let fund: SinkingFund
        let contribution: SinkingFundContribution
        let goal: Goal
    }

    private func makeSource() throws -> Fixture {
        let context = try makeContext()
        try SeedService(context: context).seedIfNeeded()

        var settingsDescriptor = FetchDescriptor<AppSettings>()
        settingsDescriptor.fetchLimit = 1
        let settings = try #require(try context.fetch(settingsDescriptor).first)
        settings.displayCurrencyCode = "USD"
        settings.weekStartsOn = 1
        settings.lockEnabled = true
        settings.lockAfterSeconds = 30
        settings.notificationsEnabled = false
        settings.privacyModeEnabled = true
        settings.largeTransactionThresholdMinor = 50_000
        settings.keepRawMessages = false
        settings.lastBackupAt = try makeDate(day: 20, hour: 8)
        settings.reinvestmentRateBasisPoints = 1_250
        settings.withholdingTaxBasisPoints = 1_500

        let group = CategoryGroup(name: "Test group", symbolName: "testtube.2", colorHex: "#123456", sortIndex: 9)
        group.seedKey = "test-group"
        group.isArchived = true
        context.insert(group)

        let category = SpendingCategory(
            name: "Test category",
            symbolName: "cart",
            colorHex: "#654321",
            isFixed: true,
            keywords: "one, two",
            sortIndex: 4
        )
        category.group = group
        category.monthlyDefaultMinor = 45_000
        category.isArchived = true
        category.kind = .income
        context.insert(category)

        let account = Account(
            name: "M-Pesa",
            kind: .mobileMoney,
            currencyCode: "KES",
            colorHex: "#00A651",
            symbolName: "phone",
            institution: "Safaricom",
            sortIndex: 3
        )
        account.note = "primary wallet"
        context.insert(account)

        let usdAccount = Account(
            name: "USD Bank",
            kind: .bank,
            currencyCode: "USD",
            colorHex: "#1B4F72",
            symbolName: "building.columns",
            institution: "Test Bank",
            sortIndex: 1
        )
        usdAccount.isArchived = true
        context.insert(usdAccount)

        let identifier = AccountIdentifier(value: "0712 345 678", type: .phone)
        identifier.account = account
        context.insert(identifier)

        let memory = MerchantMemory(merchantKey: "shell bellevue", displayName: "Shell Bellevue")
        memory.category = category
        memory.account = account
        memory.timesSeen = 4
        memory.lastSeenAt = try makeDate(day: 18, hour: 9)
        memory.autoApply = true
        memory.createdAt = try makeDate(day: 1, hour: 9)
        context.insert(memory)

        let alias = MerchantAlias(aliasKey: "shell bellevue branch")
        alias.merchantMemory = memory
        context.insert(alias)

        let conditions = SmartRuleConditions(
            amountMinMinor: 1_000,
            amountMaxMinor: 500_000,
            timeStartMinutes: 420,
            timeEndMinutes: 540,
            weekdays: [2, 3, 4, 5, 6],
            payeeContains: ["shell"],
            contextMerchant: "uber"
        )
        let smartRule = SmartRule(
            name: "Morning Shell",
            seedKey: "test-smart-rule",
            priority: 5,
            conditions: conditions,
            confidenceBoost: 0.2
        )
        smartRule.targetCategory = category
        smartRule.timesApplied = 7
        smartRule.isEnabled = false
        context.insert(smartRule)

        let ruleSet = ParseRuleSet(
            name: "Test sender",
            seedKey: "test-sender",
            senderMatchers: "TEST, OTHER",
            priority: 2
        )
        ruleSet.notes = "user-edited set"
        ruleSet.isEnabled = false
        context.insert(ruleSet)

        let parseRule = ParseRule(
            name: "Test rule",
            messageType: .income,
            pattern: #"^Paid (?<payee>.+) Ksh(?<amount>[\d,]+)"#,
            fieldPatterns: ["fee": #"cost Ksh(?<fee>[\d,]+)"#],
            priority: 3,
            sampleText: "Paid SHELL Ksh1,510.00"
        )
        parseRule.ruleSet = ruleSet
        parseRule.isEnabled = false
        context.insert(parseRule)

        let expense = LedgerEntry(
            kind: .expense,
            amountMinor: 151_000,
            feeMinor: 830,
            currencyCode: "KES",
            occurredAt: try makeDate(day: 18, hour: 11, minute: 54),
            payee: "Shell, \"Bellevue\"",
            note: "line one\nline two",
            source: .message
        )
        expense.account = account
        expense.attachSingleLine(category: category, in: context)
        expense.externalRef = "REF-1"
        expense.counterpartRef = "CP-1"
        expense.rawMessage = "Confirmed. Ksh1,510.00 paid to Nixomb Limited - Shell Bellevue."
        expense.messageSender = "M-PESA"
        expense.balanceAfterMinor = 123_456
        expense.confidence = 0.87
        expense.dedupeHash = "abc123"
        context.insert(expense)

        let softDeleted = LedgerEntry(
            kind: .expense,
            amountMinor: 1_000,
            currencyCode: "KES",
            occurredAt: try makeDate(day: 17, hour: 10),
            payee: "Old merchant",
            source: .manual
        )
        softDeleted.account = account
        softDeleted.status = .needsReview
        softDeleted.isSoftDeleted = true
        context.insert(softDeleted)

        let transfer = Transfer(occurredAt: try makeDate(day: 19, hour: 16), note: "Move to USD")
        transfer.status = .needsReview
        transfer.fromAccount = account
        transfer.toAccount = usdAccount
        context.insert(transfer)

        let outLeg = LedgerEntry(
            kind: .transferOut,
            amountMinor: 100_000,
            feeMinor: 500,
            currencyCode: "KES",
            occurredAt: transfer.occurredAt,
            payee: "USD Bank",
            source: .manual
        )
        outLeg.account = account
        outLeg.transfer = transfer
        context.insert(outLeg)

        let inLeg = LedgerEntry(
            kind: .transferIn,
            amountMinor: 77_000,
            currencyCode: "USD",
            occurredAt: transfer.occurredAt,
            payee: "M-Pesa",
            source: .manual
        )
        inLeg.account = usdAccount
        inLeg.transfer = transfer
        context.insert(inLeg)

        let loan = Loan(
            direction: .lent,
            counterparty: "Brenda",
            principalMinor: 200_000,
            currencyCode: "KES",
            startedAt: try makeDate(day: 10, hour: 9),
            dueAt: try makeDate(day: 30, hour: 9),
            note: "school fees"
        )
        loan.isSoftDeleted = true
        context.insert(loan)

        let loanEntry = LedgerEntry(
            kind: .loanOut,
            amountMinor: 200_000,
            currencyCode: "KES",
            occurredAt: loan.startedAt,
            payee: "Brenda",
            source: .manual
        )
        loanEntry.account = account
        loanEntry.loan = loan
        context.insert(loanEntry)

        let investment = Investment(
            type: .treasuryBond,
            issueNumber: "FXD1/2026/10",
            isin: "KE1000001234",
            issuer: "Central Bank",
            nominalMinor: 1_000_000,
            currencyCode: "KES",
            couponRateBasisPoints: Decimal(string: "12.857") ?? 0,
            withholdingTaxBasisPoints: 1_000,
            taxExempt: false,
            couponPeriodDays: 182,
            issueDate: try makeDate(day: 1, hour: 9),
            purchaseDate: try makeDate(day: 5, hour: 9),
            settlementDate: try makeDate(day: 6, hour: 9),
            firstCouponDate: try makeDate(day: 20, hour: 9),
            maturityDate: try makeDate(day: 20, month: 11, year: 2036, hour: 9),
            cleanPricePer100Scaled: 9_875,
            accruedInterestMinor: 12_345,
            cashInvestedMinor: 998_750,
            accountID: account.id,
            reinvestmentRateBasisPoints: 1_150,
            note: "bond note",
            status: .active,
            annualRateBasisPoints: Decimal(string: "8.25") ?? 0,
            compounding: .daily,
            startDate: try makeDate(day: 6, hour: 9),
            marketValueMinor: 1_020_000,
            couponDateOverrides: [try makeDate(day: 20, hour: 9), try makeDate(day: 20, month: 5, year: 2027, hour: 9)]
        )
        context.insert(investment)

        let purchase = InvestmentCashFlow(
            kind: .purchase,
            date: investment.purchaseDate,
            grossMinor: 998_750,
            taxMinor: 0,
            netMinor: 998_750,
            status: .paid,
            note: "purchase"
        )
        purchase.investment = investment
        context.insert(purchase)

        let coupon = InvestmentCashFlow(
            kind: .coupon,
            date: try makeDate(day: 20, hour: 9),
            grossMinor: 32_142,
            taxMinor: 3_214,
            netMinor: 28_928,
            status: .scheduled,
            note: "coupon"
        )
        coupon.investment = investment
        context.insert(coupon)

        let investmentEntry = LedgerEntry(
            kind: .investmentOut,
            amountMinor: 998_750,
            currencyCode: "KES",
            occurredAt: investment.purchaseDate,
            payee: "Central Bank",
            source: .manual
        )
        investmentEntry.account = account
        investmentEntry.investmentCashFlow = purchase
        context.insert(investmentEntry)

        let rate = ExchangeRateRecord(
            baseCode: "USD",
            quoteCode: "KES",
            rateScaled: 129_500_000,
            asOf: try makeDate(day: 15, hour: 8),
            source: .manual
        )
        context.insert(rate)

        let start = try makeDate(day: 1, hour: 0)
        let end = try makeDate(day: 1, month: 12, hour: 0)
        let period = BudgetPeriod(kind: .month, startDate: start, endDate: end)
        context.insert(period)

        let envelope = Envelope(
            period: period,
            category: category,
            limitMinor: 500_000,
            currencyCode: "USD",
            rolloverEnabled: true,
            note: "monthly food"
        )
        envelope.isArchived = true
        context.insert(envelope)

        let alert = BudgetAlert(envelope: envelope, thresholdPercent: 80, lastTriggeredPeriodStart: start)
        context.insert(alert)

        let fund = SinkingFund(
            name: "Car service",
            targetMinor: 300_000,
            currencyCode: "KES",
            monthlyAccrualMinor: 25_000,
            targetDate: try makeDate(day: 1, month: 6, year: 2027),
            category: category,
            account: account,
            note: "service fund"
        )
        fund.isArchived = true
        context.insert(fund)

        let contribution = SinkingFundContribution(
            fund: fund,
            amountMinor: 20_000,
            occurredAt: try makeDate(day: 2, hour: 10),
            account: account,
            note: "first deposit"
        )
        context.insert(contribution)

        let goal = Goal(
            name: "Emergency fund",
            targetMinor: 1_000_000,
            currencyCode: "KES",
            targetDate: try makeDate(day: 1, month: 1, year: 2027),
            account: account,
            note: "six months"
        )
        context.insert(goal)

        try context.save()

        return Fixture(
            context: context,
            settings: settings,
            group: group,
            category: category,
            account: account,
            usdAccount: usdAccount,
            identifier: identifier,
            memory: memory,
            alias: alias,
            smartRule: smartRule,
            ruleSet: ruleSet,
            parseRule: parseRule,
            expense: expense,
            softDeleted: softDeleted,
            transfer: transfer,
            outLeg: outLeg,
            inLeg: inLeg,
            loan: loan,
            loanEntry: loanEntry,
            investment: investment,
            purchase: purchase,
            coupon: coupon,
            investmentEntry: investmentEntry,
            rate: rate,
            period: period,
            envelope: envelope,
            alert: alert,
            fund: fund,
            contribution: contribution,
            goal: goal
        )
    }

    private func modelCounts(in context: ModelContext) throws -> [String: Int] {
        [
            "Account": try context.fetchCount(FetchDescriptor<Account>()),
            "AccountIdentifier": try context.fetchCount(FetchDescriptor<AccountIdentifier>()),
            "CategoryGroup": try context.fetchCount(FetchDescriptor<CategoryGroup>()),
            "SpendingCategory": try context.fetchCount(FetchDescriptor<SpendingCategory>()),
            "MerchantMemory": try context.fetchCount(FetchDescriptor<MerchantMemory>()),
            "MerchantAlias": try context.fetchCount(FetchDescriptor<MerchantAlias>()),
            "IngestMemory": try context.fetchCount(FetchDescriptor<IngestMemory>()),
            "SmartRule": try context.fetchCount(FetchDescriptor<SmartRule>()),
            "ParseRuleSet": try context.fetchCount(FetchDescriptor<ParseRuleSet>()),
            "ParseRule": try context.fetchCount(FetchDescriptor<ParseRule>()),
            "LedgerEntry": try context.fetchCount(FetchDescriptor<LedgerEntry>()),
            "Transfer": try context.fetchCount(FetchDescriptor<Transfer>()),
            "Loan": try context.fetchCount(FetchDescriptor<Loan>()),
            "Investment": try context.fetchCount(FetchDescriptor<Investment>()),
            "InvestmentCashFlow": try context.fetchCount(FetchDescriptor<InvestmentCashFlow>()),
            "ExchangeRateRecord": try context.fetchCount(FetchDescriptor<ExchangeRateRecord>()),
            "BudgetPeriod": try context.fetchCount(FetchDescriptor<BudgetPeriod>()),
            "Envelope": try context.fetchCount(FetchDescriptor<Envelope>()),
            "SinkingFund": try context.fetchCount(FetchDescriptor<SinkingFund>()),
            "SinkingFundContribution": try context.fetchCount(FetchDescriptor<SinkingFundContribution>()),
            "Goal": try context.fetchCount(FetchDescriptor<Goal>()),
            "BudgetAlert": try context.fetchCount(FetchDescriptor<BudgetAlert>()),
            "AppSettings": try context.fetchCount(FetchDescriptor<AppSettings>()),
        ]
    }

    private func restoredContext(from data: Data) throws -> (ModelContext, RestoreSummary) {
        let context = try makeFreshContext()
        let summary = try ExportService(context: context).restore(data: data)
        return (context, summary)
    }

    private func mutateJSON(
        _ data: Data,
        change: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // A hand-edited fixture is not a corruption test; the checksum test adds one back.
        object.removeValue(forKey: "checksum")
        try change(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: - Round trip

    @Test("A full backup restores every model family into a fresh context")
    func roundTripEveryFamily() throws {
        let fixture = try makeSource()
        let fixedDate = try makeDate(day: 22, hour: 0)
        let data = try ExportService(context: fixture.context).backupData(exportedAt: fixedDate)

        let (target, summary) = try restoredContext(from: data)

        #expect(try modelCounts(in: target) == modelCounts(in: fixture.context))
        #expect(summary.inserted > 0)
        #expect(summary.updated == 0)
        #expect(summary.skipped == 0)

        let expense = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.expense.id }
        )
        #expect(expense.account?.id == fixture.account.id)
        #expect(expense.primaryCategory?.id == fixture.category.id)
        #expect(expense.amountMinor == 151_000)
        #expect(expense.feeMinor == 830)
        #expect(expense.payee == "Shell, \"Bellevue\"")
        #expect(expense.note == "line one\nline two")
        #expect(expense.externalRef == "REF-1")
        #expect(expense.counterpartRef == "CP-1")
        #expect(expense.balanceAfterMinor == 123_456)
        #expect(expense.confidence == 0.87)
        #expect(expense.dedupeHash == "abc123")

        let outLeg = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.outLeg.id }
        )
        #expect(outLeg.transfer?.id == fixture.transfer.id)
        #expect(outLeg.transfer?.fromAccount?.id == fixture.account.id)
        #expect(outLeg.transfer?.toAccount?.id == fixture.usdAccount.id)
        #expect(outLeg.transfer?.legs?.count == 2)

        let loanEntry = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.loanEntry.id }
        )
        #expect(loanEntry.loan?.id == fixture.loan.id)
        #expect(loanEntry.loan?.counterparty == "Brenda")

        let investmentEntry = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.investmentEntry.id }
        )
        #expect(investmentEntry.investmentCashFlow?.id == fixture.purchase.id)
        #expect(investmentEntry.investmentCashFlow?.investment?.id == fixture.investment.id)

        let envelope = try #require(
            try target.fetch(FetchDescriptor<Envelope>()).first { $0.id == fixture.envelope.id }
        )
        #expect(envelope.period?.id == fixture.period.id)
        #expect(envelope.category?.id == fixture.category.id)
        #expect(envelope.alerts?.count == 1)

        let contribution = try #require(
            try target.fetch(FetchDescriptor<SinkingFundContribution>()).first { $0.id == fixture.contribution.id }
        )
        #expect(contribution.fund?.id == fixture.fund.id)
        #expect(contribution.account?.id == fixture.account.id)

        let goal = try #require(try target.fetch(FetchDescriptor<Goal>()).first { $0.id == fixture.goal.id })
        #expect(goal.account?.id == fixture.account.id)

        let identifier = try #require(
            try target.fetch(FetchDescriptor<AccountIdentifier>()).first { $0.id == fixture.identifier.id }
        )
        #expect(identifier.account?.id == fixture.account.id)

        let memory = try #require(
            try target.fetch(FetchDescriptor<MerchantMemory>()).first { $0.id == fixture.memory.id }
        )
        #expect(memory.category?.id == fixture.category.id)
        #expect(memory.account?.id == fixture.account.id)
        #expect(memory.aliases?.count == 1)

        let smartRule = try #require(
            try target.fetch(FetchDescriptor<SmartRule>()).first { $0.id == fixture.smartRule.id }
        )
        #expect(smartRule.targetCategory?.id == fixture.category.id)
        #expect(smartRule.conditions.payeeContains == ["shell"])
        #expect(smartRule.conditionsJSON == fixture.smartRule.conditionsJSON)

        let parseRule = try #require(
            try target.fetch(FetchDescriptor<ParseRule>()).first { $0.id == fixture.parseRule.id }
        )
        #expect(parseRule.ruleSet?.id == fixture.ruleSet.id)
        #expect(parseRule.ruleSet?.senderMatchers == "TEST, OTHER")
        #expect(parseRule.pattern == fixture.parseRule.pattern)
        #expect(parseRule.fieldPatterns == fixture.parseRule.fieldPatterns)
        #expect(parseRule.priority == 3)
        #expect(parseRule.isEnabled == false)
        #expect(parseRule.messageTypeRaw == LedgerEntryKind.income.rawValue)

        let settings = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.displayCurrencyCode == "USD")
        #expect(settings.weekStartsOn == 1)
        #expect(settings.lockEnabled)
        #expect(settings.privacyModeEnabled)
        #expect(settings.keepRawMessages == false)
        #expect(settings.reinvestmentRateBasisPoints == 1_250)
    }

    @Test("Restoring the same backup twice is idempotent")
    func idempotentMerge() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData(exportedAt: try makeDate(day: 22))
        let (target, first) = try restoredContext(from: data)
        let service = ExportService(context: target)
        let countsAfterFirst = try modelCounts(in: target)

        let second = try service.restore(data: data)

        #expect(first.inserted > 0)
        #expect(second.inserted == 0)
        #expect(second.updated == first.inserted)
        #expect(second.skipped == 0)
        #expect(try modelCounts(in: target) == countsAfterFirst)
    }

    @Test("A changed value updates the existing row instead of inserting a duplicate")
    func updateInPlace() throws {
        let fixture = try makeSource()
        let sourceService = ExportService(context: fixture.context)
        let firstData = try sourceService.backupData(exportedAt: try makeDate(day: 22))
        let (target, first) = try restoredContext(from: firstData)
        let targetService = ExportService(context: target)
        let countsAfterFirst = try modelCounts(in: target)

        fixture.account.name = "M-Pesa Updated"
        fixture.expense.amountMinor = 999_000
        fixture.category.name = "Renamed category"
        fixture.settings.displayCurrencyCode = "GBP"
        try fixture.context.save()

        let secondData = try sourceService.backupData(exportedAt: try makeDate(day: 23))
        let second = try targetService.restore(data: secondData)

        #expect(second.inserted == 0)
        #expect(second.updated == first.inserted)
        #expect(try modelCounts(in: target) == countsAfterFirst)

        let account = try #require(try target.fetch(FetchDescriptor<Account>()).first { $0.id == fixture.account.id })
        #expect(account.name == "M-Pesa Updated")

        let expense = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.expense.id }
        )
        #expect(expense.amountMinor == 999_000)

        let category = try #require(
            try target.fetch(FetchDescriptor<SpendingCategory>()).first { $0.id == fixture.category.id }
        )
        #expect(category.name == "Renamed category")

        let settings = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(settings.displayCurrencyCode == "GBP")
        #expect(try target.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test("Restoring a backup does not reset device-local backup or scan dates")
    func restorePreservesDeviceState() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let (target, _) = try restoredContext(from: data)
        let service = ExportService(context: target)

        let settings = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        let backupDate = try makeDate(day: 21, hour: 22)
        let scanDate = try makeDate(day: 21, hour: 9)
        settings.lastBackupAt = backupDate
        settings.lastNotificationScanAt = scanDate
        try target.save()

        _ = try service.restore(data: data)

        let restored = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(restored.lastBackupAt == backupDate)
        #expect(restored.lastNotificationScanAt == scanDate)
    }

    @Test("A legacy backup without category kinds restores income categories as income")
    func legacyCategoryKinds() throws {
        let source = try makeContext()
        let group = CategoryGroup(name: "Income", symbolName: "arrow.down", colorHex: "#34C759")
        group.seedKey = "income"
        source.insert(group)
        let salary = SpendingCategory(
            name: "Salary",
            symbolName: "banknote",
            colorHex: "#34C759",
            sortIndex: 0,
            kind: .income
        )
        salary.group = group
        source.insert(salary)
        try source.save()

        let data = try ExportService(context: source).backupData()
        let legacy = try mutateJSON(data) { object in
            var categories = try #require(object["categories"] as? [[String: Any]])
            for index in categories.indices {
                categories[index].removeValue(forKey: "kindRaw")
            }
            object["categories"] = categories
        }

        let target = try makeFreshContext()
        _ = try ExportService(context: target).restore(data: legacy)

        let restored = try #require(
            try target.fetch(FetchDescriptor<SpendingCategory>()).first { $0.name == "Salary" }
        )
        #expect(restored.kind == .income)
        #expect(restored.group?.seedKey == "income")
    }

    @Test("Replacing deletes target-only rows and keeps the settings row")
    func replaceMode() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData(exportedAt: try makeDate(day: 22))
        let sourceCounts = try modelCounts(in: fixture.context)

        let target = try makeFreshContext()
        let extra = Account(name: "Target only", kind: .cash, currencyCode: "KES")
        target.insert(extra)
        let settings = AppSettings()
        let backupDate = try makeDate(day: 21, hour: 22)
        settings.lastBackupAt = backupDate
        settings.displayCurrencyCode = "KES"
        settings.weekStartsOn = 2
        settings.privacyModeEnabled = false
        target.insert(settings)
        try target.save()

        let summary = try ExportService(context: target).restore(data: data, mode: .replace)

        #expect(summary.inserted > 0)
        #expect(try modelCounts(in: target) == sourceCounts)
        #expect(try target.fetch(FetchDescriptor<Account>()).contains { $0.id == extra.id } == false)

        let restoredSettings = try #require(try target.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(restoredSettings.lastBackupAt == backupDate)
        #expect(restoredSettings.displayCurrencyCode == "KES")
        #expect(restoredSettings.weekStartsOn == 2)
        #expect(restoredSettings.privacyModeEnabled == false)
    }

    @Test("Restoring into a seeded store does not duplicate starter rows")
    func restoreIntoSeededStore() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let sourceCounts = try modelCounts(in: fixture.context)

        let target = try makeContext()
        try SeedService(context: target).seedIfNeeded()

        _ = try ExportService(context: target).restore(data: data)

        #expect(try modelCounts(in: target) == sourceCounts)
        #expect(try target.fetchCount(FetchDescriptor<CategoryGroup>()) == 13)
        #expect(try target.fetchCount(FetchDescriptor<SpendingCategory>()) == 43)
        #expect(try target.fetchCount(FetchDescriptor<ParseRuleSet>()) == 3)
        #expect(try target.fetchCount(FetchDescriptor<SmartRule>()) == 8)
    }

    @Test("Archived and soft-deleted flags survive a restore")
    func flagsSurvive() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let (target, _) = try restoredContext(from: data)

        let account = try #require(
            try target.fetch(FetchDescriptor<Account>()).first { $0.id == fixture.usdAccount.id }
        )
        #expect(account.isArchived)

        let category = try #require(
            try target.fetch(FetchDescriptor<SpendingCategory>()).first { $0.id == fixture.category.id }
        )
        #expect(category.isArchived)
        #expect(category.isFixed)
        #expect(category.kind == .income)

        let group = try #require(
            try target.fetch(FetchDescriptor<CategoryGroup>()).first { $0.id == fixture.group.id }
        )
        #expect(group.isArchived)

        let envelope = try #require(
            try target.fetch(FetchDescriptor<Envelope>()).first { $0.id == fixture.envelope.id }
        )
        #expect(envelope.isArchived)
        #expect(envelope.rolloverEnabled)

        let fund = try #require(
            try target.fetch(FetchDescriptor<SinkingFund>()).first { $0.id == fixture.fund.id }
        )
        #expect(fund.isArchived)

        let softDeleted = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.softDeleted.id }
        )
        #expect(softDeleted.isSoftDeleted)
        #expect(softDeleted.status == .needsReview)

        let loan = try #require(try target.fetch(FetchDescriptor<Loan>()).first { $0.id == fixture.loan.id })
        #expect(loan.isSoftDeleted)
        #expect(loan.status == .open)
    }

    @Test("Decimal rates and scaled exchange rates round-trip exactly")
    func decimalPrecision() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let (target, _) = try restoredContext(from: data)

        let investment = try #require(
            try target.fetch(FetchDescriptor<Investment>()).first { $0.id == fixture.investment.id }
        )
        #expect(investment.couponRateBasisPoints == Decimal(string: "12.857"))
        #expect(investment.annualRateBasisPoints == Decimal(string: "8.25"))
        #expect(investment.cleanPricePer100Scaled == 9_875)
        #expect(investment.couponDateOverrides == fixture.investment.couponDateOverrides)
        #expect(investment.accountID == fixture.account.id)

        let rate = try #require(
            try target.fetch(FetchDescriptor<ExchangeRateRecord>()).first { $0.id == fixture.rate.id }
        )
        #expect(rate.rateScaled == 129_500_000)
        #expect(rate.baseCode == "USD")
        #expect(rate.quoteCode == "KES")
        #expect(rate.source == .manual)
    }

    @Test("An unsupported schema version is rejected before writing")
    func unsupportedVersion() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let mutated = try mutateJSON(data) { object in
            object["schemaVersion"] = 99
        }

        let target = try makeFreshContext()

        #expect(throws: ExportError.unsupportedVersion(99)) {
            try ExportService(context: target).restore(data: mutated)
        }

        #expect(try target.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try target.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
    }

    @Test("A missing referenced UUID is skipped and leaves the relationship nil")
    func missingReference() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let missingID = UUID()

        let mutated = try mutateJSON(data) { object in
            var entries = try #require(object["ledgerEntries"] as? [[String: Any]])
            let index = try #require(
                entries.firstIndex { $0["id"] as? String == fixture.expense.id.uuidString }
            )
            entries[index]["accountID"] = missingID.uuidString
            object["ledgerEntries"] = entries
        }

        let (target, summary) = try restoredContext(from: mutated)

        let expense = try #require(
            try target.fetch(FetchDescriptor<LedgerEntry>()).first { $0.id == fixture.expense.id }
        )
        #expect(expense.account == nil)
        #expect(expense.primaryCategory?.id == fixture.category.id)
        #expect(summary.skipped == 1)
    }

    // MARK: - CSV

    @Test("CSV has the audit header, exact decimals, escaping and newest-first rows")
    func transactionsCSV() throws {
        let context = try makeContext()
        let account = Account(name: "M-Pesa, Main", kind: .mobileMoney, currencyCode: "KES")
        context.insert(account)

        let ugx = Account(name: "UGX Cash", kind: .cash, currencyCode: "UGX")
        context.insert(ugx)

        let category = SpendingCategory(name: "Food & Drink", symbolName: "fork.knife", colorHex: "#FF9500")
        context.insert(category)

        let newer = LedgerEntry(
            kind: .expense,
            amountMinor: 151_000,
            feeMinor: 830,
            currencyCode: "KES",
            occurredAt: try makeDate(day: 21, hour: 15, minute: 7),
            payee: "Cafe, \"Central\"",
            note: "line one\nline two",
            source: .message
        )
        newer.account = account
        newer.attachSingleLine(category: category, in: context)
        newer.externalRef = "EXT-1"
        newer.counterpartRef = "CP-1"
        newer.isSoftDeleted = true
        context.insert(newer)

        let older = LedgerEntry(
            kind: .income,
            amountMinor: 12_345,
            currencyCode: "KES",
            occurredAt: try makeDate(day: 20, hour: 9),
            payee: "Shell",
            source: .manual
        )
        older.account = account
        context.insert(older)

        let zeroExponent = LedgerEntry(
            kind: .expense,
            amountMinor: 1_500,
            currencyCode: "UGX",
            occurredAt: try makeDate(day: 19, hour: 9),
            payee: "Boda",
            source: .manual
        )
        zeroExponent.account = ugx
        context.insert(zeroExponent)

        try context.save()

        let csv = try ExportService(context: context).transactionsCSV()
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        #expect(
            lines[0]
                == "id,date,kind,amount,fee,currency,account,category,tags,payee,note,source,status,externalRef,counterpartRef,transferID,loanID,investmentID,deleted"
        )
        #expect(lines.count == 4)
        #expect(lines[1].hasPrefix(newer.id.uuidString))
        #expect(lines[2].hasPrefix(older.id.uuidString))
        #expect(lines[3].hasPrefix(zeroExponent.id.uuidString))

        #expect(lines[1].contains(",1510.00,8.30,KES,"))
        #expect(lines[1].contains("\"M-Pesa, Main\""))
        #expect(lines[1].contains("\"Cafe, \"\"Central\"\"\""))
        #expect(lines[1].contains("\"line one\nline two\""))
        #expect(lines[1].hasSuffix(",true"))
        #expect(lines[1].contains(BackupCoding.string(from: newer.occurredAt)))

        #expect(lines[2].contains(",123.45,0.00,KES,"))
        #expect(lines[2].hasSuffix(",false"))
        #expect(lines[3].contains(",1500,0,UGX,"))
    }

    @Test("A tampered backup is rejected before it can change the store")
    func checksumMismatch() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData()
        let tampered = try mutateJSON(data) { object in
            var entries = try #require(object["ledgerEntries"] as? [[String: Any]])
            entries[0]["amountMinor"] = 999_999
            object["ledgerEntries"] = entries
            object["checksum"] = String(repeating: "0", count: 64)
        }

        let target = try makeFreshContext()
        #expect(throws: ExportError.checksumMismatch) {
            try ExportService(context: target).restore(data: tampered)
        }
        #expect(try target.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
    }

    @Test("CSV has a BOM and neutralises formula-leading text")
    func csvSafety() throws {
        let context = try makeContext()
        let account = Account(name: "Cash", kind: .cash, currencyCode: "KES")
        context.insert(account)
        let entry = LedgerEntry(
            kind: .expense,
            amountMinor: 1_000,
            occurredAt: try makeDate(day: 20, hour: 9),
            payee: "=HYPERLINK(\"http://example.com\")",
            note: "@cmd"
        )
        entry.account = account
        context.insert(entry)

        let service = ExportService(context: context)
        let csv = try service.transactionsCSV()
        #expect(csv.contains("'=HYPERLINK"))
        #expect(csv.contains("'@cmd"))

        let data = try service.transactionsCSVData()
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test("Suggested filenames use the local date, with an injectable time zone")
    func filenames() throws {
        let context = try makeContext()
        let service = ExportService(context: context)
        let date = try makeDate(day: 22, hour: 23, minute: 30)
        let utc = try #require(TimeZone(secondsFromGMT: 0))

        #expect(service.suggestedBackupFilename(at: date, timeZone: utc) == "manoti-backup-2026-11-22.json")
        #expect(service.suggestedCSVFilename(at: date, timeZone: utc) == "manoti-transactions-2026-11-22.csv")

        let eastAfrica = try #require(TimeZone(secondsFromGMT: 3 * 60 * 60))
        let early = try makeDate(day: 21, hour: 22, minute: 30)
        #expect(
            service.suggestedBackupFilename(at: early, timeZone: eastAfrica) == "manoti-backup-2026-11-22.json"
        )
    }

    @Test("Marking a backup records the timestamp on the settings row")
    func markBackupCompleted() throws {
        let context = try makeContext()
        let service = ExportService(context: context)
        let date = try makeDate(day: 22, hour: 20, minute: 15)

        #expect(service.lastBackupAt() == nil)

        try service.markBackupCompleted(at: date)

        #expect(service.lastBackupAt() == date)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)

        let later = try makeDate(day: 23, hour: 8)
        try service.markBackupCompleted(at: later)
        #expect(service.lastBackupAt() == later)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test("A backup can be described for a restore confirmation")
    func backupSummary() throws {
        let fixture = try makeSource()
        let data = try ExportService(context: fixture.context).backupData(exportedAt: try makeDate(day: 22))

        let summary = try ExportService(context: fixture.context).backupSummary(data: data)

        #expect(summary.contains("entries"))
        #expect(summary.contains("accounts"))
        #expect(summary.contains("2026"))
    }
}
