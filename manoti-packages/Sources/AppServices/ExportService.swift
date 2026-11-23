//
//  ExportService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

nonisolated public struct RestoreSummary: Equatable, Sendable {
    public let inserted: Int
    public let updated: Int
    public let skipped: Int

    public init(inserted: Int, updated: Int, skipped: Int) {
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
    }
}

nonisolated public enum ExportError: Error, Equatable {
    case unsupportedVersion(Int)
    case decodeFailed
    case checksumMismatch
    case invalidCSV
}

nonisolated public enum RestoreMode: Sendable {
    case merge
    case replace
}

/// Writes a full JSON backup, merges one back in by UUID, and exports the ledger as CSV.
///
/// Restore is additive and idempotent: rows are matched by `id`, never deleted, and a
/// foreign key that no longer exists becomes `nil` and is reported in `RestoreSummary`.
/// `replace` explicitly deletes user rows first; settings and device-local dates stay.
@Observable
public final class ExportService: Loggable {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Backup

    public func backupData(exportedAt: Date = Date()) throws -> Data {
        var document = try makeDocument(exportedAt: exportedAt)
        document.checksum = try BackupChecksum.value(for: document)
        return try BackupCoding.encoder().encode(document)
    }

    public func restore(data: Data) throws -> RestoreSummary {
        try restore(data: data, mode: .merge)
    }

    public func restore(data: Data, mode: RestoreMode) throws -> RestoreSummary {
        let document = try decodeDocument(data)

        do {
            if mode == .replace {
                try deleteUserRows()
            }

            let summary = try merge(document, applySettings: mode == .merge)
            try inferKindsForLegacyCategories(document)
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Backups written before category kinds existed have no `kindRaw`. Restore them as
    /// expense by default, then put the known income rows back where they belong.
    private func inferKindsForLegacyCategories(_ document: BackupDocument) throws {
        let missing = Set(document.categories.filter { $0.kindRaw == nil }.map(\.id))
        guard !missing.isEmpty else {
            return
        }

        let incomeNames: Set<String> = ["Salary", "Business", "Refund", "Gift received", "Other income"]
        var changed = false

        for category in try context.fetch(FetchDescriptor<SpendingCategory>())
        where missing.contains(category.id) && category.kind == .expense {
            let group = category.group
            let isIncomeGroup =
                group?.seedKey == "income"
                || group?.name.caseInsensitiveCompare("Income") == .orderedSame

            if isIncomeGroup || incomeNames.contains(category.name) {
                category.kind = .income
                changed = true
            }
        }

        if changed {
            try context.save()
        }
    }

    /// A short human description of a backup file, for a restore confirmation.
    public func backupSummary(data: Data) throws -> String {
        let document = try decodeDocument(data)
        let date = document.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let entries = document.ledgerEntries.count
        let accounts = document.accounts.count
        return
            "\(date) · \(entries) \(entries == 1 ? "entry" : "entries") · \(accounts) \(accounts == 1 ? "account" : "accounts")"
    }

    private func deleteUserRows() throws {
        try context.delete(model: SinkingFundContribution.self)
        try context.delete(model: SinkingFund.self)
        try context.delete(model: BudgetAlert.self)
        try context.delete(model: Envelope.self)
        try context.delete(model: BudgetPeriod.self)
        try context.delete(model: Goal.self)
        try context.delete(model: InvestmentCashFlow.self)
        try context.delete(model: Investment.self)
        try context.delete(model: LedgerEntry.self)
        try context.delete(model: Transfer.self)
        try context.delete(model: Loan.self)
        try context.delete(model: MerchantAlias.self)
        try context.delete(model: MerchantMemory.self)
        try context.delete(model: SmartRule.self)
        try context.delete(model: ParseRule.self)
        try context.delete(model: ParseRuleSet.self)
        try context.delete(model: AccountIdentifier.self)
        try context.delete(model: Account.self)
        try context.delete(model: SpendingCategory.self)
        try context.delete(model: CategoryGroup.self)
        try context.delete(model: ExchangeRateRecord.self)
        try context.delete(model: ReconcileMessage.self)
        try context.delete(model: ReconcileSession.self)
        try context.delete(model: ContextWindow.self)
        // No save here: the replace restore commits the deletes and the restored rows in
        // one transaction, so a failure cannot leave an empty store behind.
        log("Deleting user rows before replacing from a backup", level: .warning)
    }

    private func decodeDocument(_ data: Data) throws -> BackupDocument {
        struct Header: Decodable {
            let schemaVersion: Int?
        }

        // Read the version before building any model, so a newer file gets the correct
        // message instead of a generic decode failure.
        if let header = try? JSONDecoder().decode(Header.self, from: data),
            let version = header.schemaVersion,
            version != BackupDocument.currentSchemaVersion
        {
            throw ExportError.unsupportedVersion(version)
        }

        let document: BackupDocument

        do {
            document = try BackupCoding.decoder().decode(BackupDocument.self, from: data)
        } catch {
            log("Backup decode failed: \(error.localizedDescription)", level: .error)
            throw ExportError.decodeFailed
        }

        guard document.schemaVersion == BackupDocument.currentSchemaVersion else {
            throw ExportError.unsupportedVersion(document.schemaVersion)
        }

        if let checksum = document.checksum,
            try BackupChecksum.value(for: document) != checksum
        {
            throw ExportError.checksumMismatch
        }

        return document
    }

    // MARK: - Backup state

    public func lastBackupAt() -> Date? {
        try? context.fetch(FetchDescriptor<AppSettings>()).first?.lastBackupAt
    }

    /// Records that a backup file was written successfully.
    public func markBackupCompleted(at date: Date = Date()) throws {
        let settings: AppSettings

        if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first {
            settings = existing
        } else {
            let created = AppSettings()
            context.insert(created)
            settings = created
        }

        settings.lastBackupAt = date
        try context.save()
        ManotiNotifications.postDataChanged()
    }

    // MARK: - CSV

    public func transactionsCSV() throws -> String {
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let ordered = entries.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }

        var lines = [
            "id,date,kind,amount,fee,currency,account,category,payee,note,source,status,externalRef,counterpartRef,transferID,loanID,investmentID,deleted"
        ]

        for entry in ordered {
            let exponent = entry.currency.exponent
            let fields = [
                entry.id.uuidString,
                BackupCoding.string(from: entry.occurredAt),
                entry.kindRaw,
                majorUnitString(minorUnits: entry.amountMinor, exponent: exponent),
                majorUnitString(minorUnits: entry.feeMinor, exponent: exponent),
                entry.currencyCode,
                entry.account?.displayName ?? "",
                entry.category?.name ?? "",
                entry.payee,
                entry.note,
                entry.sourceRaw,
                entry.statusRaw,
                entry.externalRef,
                entry.counterpartRef,
                entry.transfer?.id.uuidString ?? "",
                entry.loan?.id.uuidString ?? "",
                entry.investmentCashFlow?.investment?.id.uuidString ?? "",
                entry.isSoftDeleted ? "true" : "false",
            ]
            // Only free text needs the spreadsheet-formula guard; amounts keep their sign.
            let textColumns: Set<Int> = [6, 7, 8, 9, 12, 13]
            let escaped = fields.enumerated().map { index, field in
                escapeCSV(textColumns.contains(index) ? guardedCSVText(field) : field)
            }
            lines.append(escaped.joined(separator: ","))
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// UTF-8 with a BOM, so Excel opens non-ASCII payees correctly.
    public func transactionsCSVData() throws -> Data {
        Data(("\u{FEFF}" + (try transactionsCSV())).utf8)
    }

    public func suggestedBackupFilename(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "manoti-backup-\(dateStamp(for: date, timeZone: timeZone)).json"
    }

    public func suggestedCSVFilename(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "manoti-transactions-\(dateStamp(for: date, timeZone: timeZone)).csv"
    }

    // MARK: - Document assembly

    private func makeDocument(exportedAt: Date) throws -> BackupDocument {
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let groups = try context.fetch(FetchDescriptor<CategoryGroup>())
        let categories = try context.fetch(FetchDescriptor<SpendingCategory>())
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let identifiers = try context.fetch(FetchDescriptor<AccountIdentifier>())
        let merchantMemories = try context.fetch(FetchDescriptor<MerchantMemory>())
        let merchantAliases = try context.fetch(FetchDescriptor<MerchantAlias>())
        let smartRules = try context.fetch(FetchDescriptor<SmartRule>())
        let ruleSets = try context.fetch(FetchDescriptor<ParseRuleSet>())
        let parseRules = try context.fetch(FetchDescriptor<ParseRule>())
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let transfers = try context.fetch(FetchDescriptor<Transfer>())
        let loans = try context.fetch(FetchDescriptor<Loan>())
        let investments = try context.fetch(FetchDescriptor<Investment>())
        let cashFlows = try context.fetch(FetchDescriptor<InvestmentCashFlow>())
        let rates = try context.fetch(FetchDescriptor<ExchangeRateRecord>())
        let periods = try context.fetch(FetchDescriptor<BudgetPeriod>())
        let envelopes = try context.fetch(FetchDescriptor<Envelope>())
        let funds = try context.fetch(FetchDescriptor<SinkingFund>())
        let contributions = try context.fetch(FetchDescriptor<SinkingFundContribution>())
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let alerts = try context.fetch(FetchDescriptor<BudgetAlert>())

        return BackupDocument(
            schemaVersion: BackupDocument.currentSchemaVersion,
            exportedAt: exportedAt,
            appVersion: AppInfo.version,
            settings: settings.map(backup),
            categoryGroups: sortedByID(groups, id: \.id).map(backup),
            categories: sortedByID(categories, id: \.id).map(backup),
            accounts: sortedByID(accounts, id: \.id).map(backup),
            accountIdentifiers: sortedByID(identifiers, id: \.id).map(backup),
            merchantMemories: sortedByID(merchantMemories, id: \.id).map(backup),
            merchantAliases: sortedByID(merchantAliases, id: \.id).map(backup),
            smartRules: sortedByID(smartRules, id: \.id).map(backup),
            parseRuleSets: sortedByID(ruleSets, id: \.id).map(backup),
            parseRules: sortedByID(parseRules, id: \.id).map(backup),
            ledgerEntries: sortedByID(entries, id: \.id).map(backup),
            transfers: sortedByID(transfers, id: \.id).map(backup),
            loans: sortedByID(loans, id: \.id).map(backup),
            investments: sortedByID(investments, id: \.id).map(backup),
            investmentCashFlows: sortedByID(cashFlows, id: \.id).map(backup),
            exchangeRates: sortedByID(rates, id: \.id).map(backup),
            budgetPeriods: sortedByID(periods, id: \.id).map(backup),
            envelopes: sortedByID(envelopes, id: \.id).map(backup),
            sinkingFunds: sortedByID(funds, id: \.id).map(backup),
            sinkingFundContributions: sortedByID(contributions, id: \.id).map(backup),
            goals: sortedByID(goals, id: \.id).map(backup),
            budgetAlerts: sortedByID(alerts, id: \.id).map(backup)
        )
    }

    private func backup(_ settings: AppSettings) -> BackupAppSettings {
        BackupAppSettings(
            id: settings.id,
            displayCurrencyCode: settings.displayCurrencyCode,
            weekStartsOn: settings.weekStartsOn,
            lockEnabled: settings.lockEnabled,
            lockAfterSeconds: settings.lockAfterSeconds,
            notificationsEnabled: settings.notificationsEnabled,
            dailyReminderEnabled: settings.dailyReminderEnabled,
            inboxReminderEnabled: settings.inboxReminderEnabled,
            weeklySummaryEnabled: settings.weeklySummaryEnabled,
            budgetAlertsEnabled: settings.budgetAlertsEnabled,
            largeTransactionAlertsEnabled: settings.largeTransactionAlertsEnabled,
            privacyModeEnabled: settings.privacyModeEnabled,
            largeTransactionThresholdMinor: settings.largeTransactionThresholdMinor,
            lastNotificationScanAt: settings.lastNotificationScanAt,
            keepRawMessages: settings.keepRawMessages,
            lastBackupAt: settings.lastBackupAt,
            reinvestmentRateBasisPoints: settings.reinvestmentRateBasisPoints,
            withholdingTaxBasisPoints: settings.withholdingTaxBasisPoints
        )
    }

    private func backup(_ group: CategoryGroup) -> BackupCategoryGroup {
        BackupCategoryGroup(
            id: group.id,
            name: group.name,
            symbolName: group.symbolName,
            colorHex: group.colorHex,
            sortIndex: group.sortIndex,
            isArchived: group.isArchived,
            seedKey: group.seedKey
        )
    }

    private func backup(_ category: SpendingCategory) -> BackupSpendingCategory {
        BackupSpendingCategory(
            id: category.id,
            name: category.name,
            symbolName: category.symbolName,
            colorHex: category.colorHex,
            isFixed: category.isFixed,
            monthlyDefaultMinor: category.monthlyDefaultMinor,
            keywords: category.keywords,
            sortIndex: category.sortIndex,
            isArchived: category.isArchived,
            groupID: category.group?.id,
            kindRaw: category.kindRaw
        )
    }

    private func backup(_ account: Account) -> BackupAccount {
        BackupAccount(
            id: account.id,
            name: account.name,
            kindRaw: account.kindRaw,
            currencyCode: account.currencyCode,
            colorHex: account.colorHex,
            symbolName: account.symbolName,
            institution: account.institution,
            note: account.note,
            isArchived: account.isArchived,
            sortIndex: account.sortIndex,
            createdAt: account.createdAt,
            updatedAt: account.updatedAt
        )
    }

    private func backup(_ identifier: AccountIdentifier) -> BackupAccountIdentifier {
        BackupAccountIdentifier(
            id: identifier.id,
            value: identifier.value,
            typeRaw: identifier.typeRaw,
            accountID: identifier.account?.id
        )
    }

    private func backup(_ memory: MerchantMemory) -> BackupMerchantMemory {
        BackupMerchantMemory(
            id: memory.id,
            merchantKey: memory.merchantKey,
            displayName: memory.displayName,
            categoryID: memory.category?.id,
            accountID: memory.account?.id,
            timesSeen: memory.timesSeen,
            lastSeenAt: memory.lastSeenAt,
            autoApply: memory.autoApply,
            createdAt: memory.createdAt
        )
    }

    private func backup(_ alias: MerchantAlias) -> BackupMerchantAlias {
        BackupMerchantAlias(
            id: alias.id,
            aliasKey: alias.aliasKey,
            merchantMemoryID: alias.merchantMemory?.id
        )
    }

    private func backup(_ rule: SmartRule) -> BackupSmartRule {
        BackupSmartRule(
            id: rule.id,
            name: rule.name,
            seedKey: rule.seedKey,
            isEnabled: rule.isEnabled,
            priority: rule.priority,
            conditionsJSON: rule.conditionsJSON,
            targetCategoryID: rule.targetCategory?.id,
            confidenceBoost: rule.confidenceBoost,
            timesApplied: rule.timesApplied,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt
        )
    }

    private func backup(_ ruleSet: ParseRuleSet) -> BackupParseRuleSet {
        BackupParseRuleSet(
            id: ruleSet.id,
            name: ruleSet.name,
            seedKey: ruleSet.seedKey,
            senderMatchers: ruleSet.senderMatchers,
            priority: ruleSet.priority,
            isEnabled: ruleSet.isEnabled,
            notes: ruleSet.notes
        )
    }

    private func backup(_ rule: ParseRule) -> BackupParseRule {
        BackupParseRule(
            id: rule.id,
            name: rule.name,
            messageTypeRaw: rule.messageTypeRaw,
            pattern: rule.pattern,
            fieldPatternsJSON: rule.fieldPatternsJSON,
            priority: rule.priority,
            isEnabled: rule.isEnabled,
            sampleText: rule.sampleText,
            ruleSetID: rule.ruleSet?.id
        )
    }

    private func backup(_ entry: LedgerEntry) -> BackupLedgerEntry {
        BackupLedgerEntry(
            id: entry.id,
            occurredAt: entry.occurredAt,
            createdAt: entry.createdAt,
            kindRaw: entry.kindRaw,
            amountMinor: entry.amountMinor,
            feeMinor: entry.feeMinor,
            currencyCode: entry.currencyCode,
            accountID: entry.account?.id,
            categoryID: entry.category?.id,
            payee: entry.payee,
            note: entry.note,
            sourceRaw: entry.sourceRaw,
            externalRef: entry.externalRef,
            counterpartRef: entry.counterpartRef,
            rawMessage: entry.rawMessage,
            messageSender: entry.messageSender,
            balanceAfterMinor: entry.balanceAfterMinor,
            statusRaw: entry.statusRaw,
            confidence: entry.confidence,
            dedupeHash: entry.dedupeHash,
            isSoftDeleted: entry.isSoftDeleted,
            transferID: entry.transfer?.id,
            loanID: entry.loan?.id,
            investmentCashFlowID: entry.investmentCashFlow?.id
        )
    }

    private func backup(_ transfer: Transfer) -> BackupTransfer {
        BackupTransfer(
            id: transfer.id,
            occurredAt: transfer.occurredAt,
            statusRaw: transfer.statusRaw,
            note: transfer.note,
            createdAt: transfer.createdAt,
            fromAccountID: transfer.fromAccount?.id,
            toAccountID: transfer.toAccount?.id
        )
    }

    private func backup(_ loan: Loan) -> BackupLoan {
        BackupLoan(
            id: loan.id,
            directionRaw: loan.directionRaw,
            counterparty: loan.counterparty,
            principalMinor: loan.principalMinor,
            currencyCode: loan.currencyCode,
            startedAt: loan.startedAt,
            dueAt: loan.dueAt,
            note: loan.note,
            statusRaw: loan.statusRaw,
            createdAt: loan.createdAt,
            updatedAt: loan.updatedAt,
            isSoftDeleted: loan.isSoftDeleted,
            entryIDs: sortedByID(loan.entries ?? [], id: \.id).map(\.id)
        )
    }

    private func backup(_ investment: Investment) -> BackupInvestment {
        BackupInvestment(
            id: investment.id,
            typeRaw: investment.typeRaw,
            issueNumber: investment.issueNumber,
            isin: investment.isin,
            issuer: investment.issuer,
            nominalMinor: investment.nominalMinor,
            currencyCode: investment.currencyCode,
            couponRateBasisPoints: BackupDecimal(investment.couponRateBasisPoints),
            withholdingTaxBasisPoints: investment.withholdingTaxBasisPoints,
            taxExempt: investment.taxExempt,
            couponPeriodDays: investment.couponPeriodDays,
            issueDate: investment.issueDate,
            purchaseDate: investment.purchaseDate,
            settlementDate: investment.settlementDate,
            firstCouponDate: investment.firstCouponDate,
            maturityDate: investment.maturityDate,
            cleanPricePer100Scaled: investment.cleanPricePer100Scaled,
            accruedInterestMinor: investment.accruedInterestMinor,
            cashInvestedMinor: investment.cashInvestedMinor,
            accountID: investment.accountID,
            reinvestmentRateBasisPoints: investment.reinvestmentRateBasisPoints,
            note: investment.note,
            statusRaw: investment.statusRaw,
            isSoftDeleted: investment.isSoftDeleted,
            createdAt: investment.createdAt,
            updatedAt: investment.updatedAt,
            annualRateBasisPoints: BackupDecimal(investment.annualRateBasisPoints),
            compoundingRaw: investment.compoundingRaw,
            startDate: investment.startDate,
            marketValueMinor: investment.marketValueMinor,
            couponDateOverrides: investment.couponDateOverrides
        )
    }

    private func backup(_ cashFlow: InvestmentCashFlow) -> BackupInvestmentCashFlow {
        BackupInvestmentCashFlow(
            id: cashFlow.id,
            kindRaw: cashFlow.kindRaw,
            date: cashFlow.date,
            grossMinor: cashFlow.grossMinor,
            taxMinor: cashFlow.taxMinor,
            netMinor: cashFlow.netMinor,
            statusRaw: cashFlow.statusRaw,
            note: cashFlow.note,
            isSoftDeleted: cashFlow.isSoftDeleted,
            createdAt: cashFlow.createdAt,
            investmentID: cashFlow.investment?.id,
            ledgerEntryID: cashFlow.ledgerEntry?.id
        )
    }

    private func backup(_ rate: ExchangeRateRecord) -> BackupExchangeRate {
        BackupExchangeRate(
            id: rate.id,
            baseCode: rate.baseCode,
            quoteCode: rate.quoteCode,
            rateScaled: rate.rateScaled,
            asOf: rate.asOf,
            sourceRaw: rate.sourceRaw,
            createdAt: rate.createdAt
        )
    }

    private func backup(_ period: BudgetPeriod) -> BackupBudgetPeriod {
        BackupBudgetPeriod(
            id: period.id,
            kindRaw: period.kindRaw,
            startDate: period.startDate,
            endDate: period.endDate,
            createdAt: period.createdAt
        )
    }

    private func backup(_ envelope: Envelope) -> BackupEnvelope {
        BackupEnvelope(
            id: envelope.id,
            limitMinor: envelope.limitMinor,
            currencyCode: envelope.currencyCode,
            rolloverEnabled: envelope.rolloverEnabled,
            note: envelope.note,
            isArchived: envelope.isArchived,
            createdAt: envelope.createdAt,
            periodID: envelope.period?.id,
            categoryID: envelope.category?.id
        )
    }

    private func backup(_ fund: SinkingFund) -> BackupSinkingFund {
        BackupSinkingFund(
            id: fund.id,
            name: fund.name,
            targetMinor: fund.targetMinor,
            currencyCode: fund.currencyCode,
            monthlyAccrualMinor: fund.monthlyAccrualMinor,
            targetDate: fund.targetDate,
            note: fund.note,
            isArchived: fund.isArchived,
            createdAt: fund.createdAt,
            categoryID: fund.category?.id,
            accountID: fund.account?.id
        )
    }

    private func backup(_ contribution: SinkingFundContribution) -> BackupSinkingFundContribution {
        BackupSinkingFundContribution(
            id: contribution.id,
            amountMinor: contribution.amountMinor,
            occurredAt: contribution.occurredAt,
            note: contribution.note,
            createdAt: contribution.createdAt,
            fundID: contribution.fund?.id,
            accountID: contribution.account?.id
        )
    }

    private func backup(_ goal: Goal) -> BackupGoal {
        BackupGoal(
            id: goal.id,
            name: goal.name,
            targetMinor: goal.targetMinor,
            currencyCode: goal.currencyCode,
            targetDate: goal.targetDate,
            note: goal.note,
            isArchived: goal.isArchived,
            createdAt: goal.createdAt,
            accountID: goal.account?.id
        )
    }

    private func backup(_ alert: BudgetAlert) -> BackupBudgetAlert {
        BackupBudgetAlert(
            id: alert.id,
            thresholdPercent: alert.thresholdPercent,
            lastTriggeredPeriodStart: alert.lastTriggeredPeriodStart,
            createdAt: alert.createdAt,
            envelopeID: alert.envelope?.id
        )
    }

    // MARK: - Merge

    private func merge(_ document: BackupDocument, applySettings: Bool = true) throws -> RestoreSummary {
        var inserted = 0
        var updated = 0
        var skipped = 0

        var groups = try index(CategoryGroup.self, id: \.id)
        var categories = try index(SpendingCategory.self, id: \.id)
        var accounts = try index(Account.self, id: \.id)
        var identifiers = try index(AccountIdentifier.self, id: \.id)
        var memories = try index(MerchantMemory.self, id: \.id)
        var aliases = try index(MerchantAlias.self, id: \.id)
        var smartRules = try index(SmartRule.self, id: \.id)
        var ruleSets = try index(ParseRuleSet.self, id: \.id)
        var parseRules = try index(ParseRule.self, id: \.id)
        var entries = try index(LedgerEntry.self, id: \.id)
        var transfers = try index(Transfer.self, id: \.id)
        var loans = try index(Loan.self, id: \.id)
        var investments = try index(Investment.self, id: \.id)
        var cashFlows = try index(InvestmentCashFlow.self, id: \.id)
        var rates = try index(ExchangeRateRecord.self, id: \.id)
        var periods = try index(BudgetPeriod.self, id: \.id)
        var envelopes = try index(Envelope.self, id: \.id)
        var funds = try index(SinkingFund.self, id: \.id)
        var contributions = try index(SinkingFundContribution.self, id: \.id)
        var goals = try index(Goal.self, id: \.id)
        var alerts = try index(BudgetAlert.self, id: \.id)

        for backup in document.categoryGroups {
            if upsert(
                backup.id,
                in: &groups,
                matching: { !backup.seedKey.isEmpty && $0.seedKey == backup.seedKey },
                create: {
                    CategoryGroup(
                        name: backup.name,
                        symbolName: backup.symbolName,
                        colorHex: backup.colorHex,
                        sortIndex: backup.sortIndex
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.categories {
            if upsert(
                backup.id,
                in: &categories,
                matching: {
                    $0.name.caseInsensitiveCompare(backup.name) == .orderedSame
                        && $0.kind.rawValue == (backup.kindRaw ?? CategoryKind.expense.rawValue)
                },
                create: {
                    SpendingCategory(
                        name: backup.name,
                        symbolName: backup.symbolName,
                        colorHex: backup.colorHex,
                        isFixed: backup.isFixed,
                        keywords: backup.keywords,
                        sortIndex: backup.sortIndex
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.accounts {
            if upsert(
                backup.id,
                in: &accounts,
                create: {
                    Account(
                        name: backup.name,
                        kind: AccountKind(rawValue: backup.kindRaw) ?? .bank,
                        currencyCode: backup.currencyCode,
                        colorHex: backup.colorHex,
                        symbolName: backup.symbolName,
                        institution: backup.institution,
                        sortIndex: backup.sortIndex
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.accountIdentifiers {
            if upsert(
                backup.id,
                in: &identifiers,
                create: {
                    AccountIdentifier(
                        value: backup.value,
                        type: AccountIdentifierType(rawValue: backup.typeRaw) ?? .accountNumber
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.merchantMemories {
            if upsert(
                backup.id,
                in: &memories,
                matching: { $0.merchantKey == backup.merchantKey },
                create: { MerchantMemory(merchantKey: backup.merchantKey, displayName: backup.displayName) },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.merchantAliases {
            if upsert(
                backup.id,
                in: &aliases,
                create: { MerchantAlias(aliasKey: backup.aliasKey) },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.smartRules {
            if upsert(
                backup.id,
                in: &smartRules,
                matching: { !backup.seedKey.isEmpty && $0.seedKey == backup.seedKey },
                create: {
                    SmartRule(
                        name: backup.name,
                        seedKey: backup.seedKey,
                        priority: backup.priority,
                        conditions: SmartRuleConditions()
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.parseRuleSets {
            if upsert(
                backup.id,
                in: &ruleSets,
                matching: { !backup.seedKey.isEmpty && $0.seedKey == backup.seedKey },
                create: {
                    ParseRuleSet(
                        name: backup.name,
                        seedKey: backup.seedKey,
                        senderMatchers: backup.senderMatchers,
                        priority: backup.priority
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.parseRules {
            if upsert(
                backup.id,
                in: &parseRules,
                matching: {
                    $0.name.caseInsensitiveCompare(backup.name) == .orderedSame
                        && $0.messageTypeRaw == backup.messageTypeRaw
                },
                create: {
                    ParseRule(
                        name: backup.name,
                        messageType: LedgerEntryKind(rawValue: backup.messageTypeRaw) ?? .expense,
                        pattern: backup.pattern,
                        priority: backup.priority,
                        sampleText: backup.sampleText
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.ledgerEntries {
            if upsert(
                backup.id,
                in: &entries,
                create: {
                    LedgerEntry(
                        kind: LedgerEntryKind(rawValue: backup.kindRaw) ?? .expense,
                        amountMinor: backup.amountMinor,
                        feeMinor: backup.feeMinor,
                        currencyCode: backup.currencyCode,
                        occurredAt: backup.occurredAt,
                        payee: backup.payee,
                        note: backup.note,
                        source: LedgerEntrySource(rawValue: backup.sourceRaw) ?? .manual
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.transfers {
            if upsert(
                backup.id,
                in: &transfers,
                create: { Transfer(occurredAt: backup.occurredAt, note: backup.note) },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.loans {
            if upsert(
                backup.id,
                in: &loans,
                create: {
                    Loan(
                        direction: LoanDirection(rawValue: backup.directionRaw) ?? .lent,
                        counterparty: backup.counterparty,
                        principalMinor: backup.principalMinor,
                        currencyCode: backup.currencyCode,
                        startedAt: backup.startedAt,
                        dueAt: backup.dueAt,
                        note: backup.note
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.investments {
            if upsert(
                backup.id,
                in: &investments,
                create: {
                    Investment(
                        type: InvestmentType(rawValue: backup.typeRaw) ?? .treasuryBond,
                        currencyCode: backup.currencyCode,
                        purchaseDate: backup.purchaseDate
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.investmentCashFlows {
            if upsert(
                backup.id,
                in: &cashFlows,
                create: {
                    InvestmentCashFlow(
                        kind: InvestmentCashFlowKind(rawValue: backup.kindRaw) ?? .coupon,
                        date: backup.date,
                        grossMinor: backup.grossMinor,
                        taxMinor: backup.taxMinor,
                        netMinor: backup.netMinor,
                        status: InvestmentCashFlowStatus(rawValue: backup.statusRaw) ?? .scheduled,
                        note: backup.note
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.budgetPeriods {
            if upsert(
                backup.id,
                in: &periods,
                create: {
                    BudgetPeriod(
                        kind: BudgetPeriodKind(rawValue: backup.kindRaw) ?? .month,
                        startDate: backup.startDate,
                        endDate: backup.endDate
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.envelopes {
            if upsert(
                backup.id,
                in: &envelopes,
                create: {
                    Envelope(
                        limitMinor: backup.limitMinor,
                        currencyCode: backup.currencyCode,
                        rolloverEnabled: backup.rolloverEnabled,
                        note: backup.note
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.sinkingFunds {
            if upsert(
                backup.id,
                in: &funds,
                create: { SinkingFund(name: backup.name) },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.sinkingFundContributions {
            if upsert(
                backup.id,
                in: &contributions,
                create: {
                    SinkingFundContribution(
                        amountMinor: backup.amountMinor,
                        occurredAt: backup.occurredAt,
                        note: backup.note
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.goals {
            if upsert(
                backup.id,
                in: &goals,
                create: { Goal(name: backup.name) },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.budgetAlerts {
            if upsert(
                backup.id,
                in: &alerts,
                create: {
                    BudgetAlert(
                        thresholdPercent: backup.thresholdPercent,
                        lastTriggeredPeriodStart: backup.lastTriggeredPeriodStart
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        for backup in document.exchangeRates {
            if upsert(
                backup.id,
                in: &rates,
                create: {
                    ExchangeRateRecord(
                        baseCode: backup.baseCode,
                        quoteCode: backup.quoteCode,
                        rateScaled: backup.rateScaled,
                        asOf: backup.asOf,
                        source: ExchangeRateSource(rawValue: backup.sourceRaw) ?? .manual
                    )
                },
                apply: { apply(backup, to: $0) }
            ) {
                inserted += 1
            } else {
                updated += 1
            }
        }

        if applySettings, let backup = document.settings {
            var descriptor = FetchDescriptor<AppSettings>()
            descriptor.fetchLimit = 1

            if let settings = try context.fetch(descriptor).first {
                apply(backup, to: settings)
                updated += 1
            } else {
                let settings = AppSettings()
                settings.id = backup.id
                apply(backup, to: settings)
                context.insert(settings)
                inserted += 1
            }
        }

        // Relationships are resolved only after every row exists.

        for backup in document.categories {
            guard let category = categories[backup.id] else {
                continue
            }

            if let groupID = backup.groupID {
                if let group = groups[groupID] {
                    category.group = group
                } else {
                    category.group = nil
                    skipped += 1
                }
            } else {
                category.group = nil
            }
        }

        for backup in document.accountIdentifiers {
            guard let identifier = identifiers[backup.id] else {
                continue
            }

            if let accountID = backup.accountID {
                if let account = accounts[accountID] {
                    identifier.account = account
                } else {
                    identifier.account = nil
                    skipped += 1
                }
            } else {
                identifier.account = nil
            }
        }

        for backup in document.merchantMemories {
            guard let memory = memories[backup.id] else {
                continue
            }

            if let categoryID = backup.categoryID {
                if let category = categories[categoryID] {
                    memory.category = category
                } else {
                    memory.category = nil
                    skipped += 1
                }
            } else {
                memory.category = nil
            }

            if let accountID = backup.accountID {
                if let account = accounts[accountID] {
                    memory.account = account
                } else {
                    memory.account = nil
                    skipped += 1
                }
            } else {
                memory.account = nil
            }
        }

        for backup in document.merchantAliases {
            guard let alias = aliases[backup.id] else {
                continue
            }

            if let memoryID = backup.merchantMemoryID {
                if let memory = memories[memoryID] {
                    alias.merchantMemory = memory
                } else {
                    alias.merchantMemory = nil
                    skipped += 1
                }
            } else {
                alias.merchantMemory = nil
            }
        }

        for backup in document.smartRules {
            guard let rule = smartRules[backup.id] else {
                continue
            }

            if let categoryID = backup.targetCategoryID {
                if let category = categories[categoryID] {
                    rule.targetCategory = category
                } else {
                    rule.targetCategory = nil
                    skipped += 1
                }
            } else {
                rule.targetCategory = nil
            }
        }

        for backup in document.parseRules {
            guard let rule = parseRules[backup.id] else {
                continue
            }

            if let ruleSetID = backup.ruleSetID {
                if let ruleSet = ruleSets[ruleSetID] {
                    rule.ruleSet = ruleSet
                } else {
                    rule.ruleSet = nil
                    skipped += 1
                }
            } else {
                rule.ruleSet = nil
            }
        }

        for backup in document.ledgerEntries {
            guard let entry = entries[backup.id] else {
                continue
            }

            if let accountID = backup.accountID {
                if let account = accounts[accountID] {
                    entry.account = account
                } else {
                    entry.account = nil
                    skipped += 1
                }
            } else {
                entry.account = nil
            }

            if let categoryID = backup.categoryID {
                if let category = categories[categoryID] {
                    entry.category = category
                } else {
                    entry.category = nil
                    skipped += 1
                }
            } else {
                entry.category = nil
            }

            if let transferID = backup.transferID {
                if let transfer = transfers[transferID] {
                    entry.transfer = transfer
                } else {
                    entry.transfer = nil
                    skipped += 1
                }
            } else {
                entry.transfer = nil
            }

            if let loanID = backup.loanID {
                if let loan = loans[loanID] {
                    entry.loan = loan
                } else {
                    entry.loan = nil
                    skipped += 1
                }
            } else {
                entry.loan = nil
            }

            if let cashFlowID = backup.investmentCashFlowID {
                if let cashFlow = cashFlows[cashFlowID] {
                    entry.investmentCashFlow = cashFlow
                } else {
                    entry.investmentCashFlow = nil
                    skipped += 1
                }
            } else {
                entry.investmentCashFlow = nil
            }
        }

        for backup in document.transfers {
            guard let transfer = transfers[backup.id] else {
                continue
            }

            if let accountID = backup.fromAccountID {
                if let account = accounts[accountID] {
                    transfer.fromAccount = account
                } else {
                    transfer.fromAccount = nil
                    skipped += 1
                }
            } else {
                transfer.fromAccount = nil
            }

            if let accountID = backup.toAccountID {
                if let account = accounts[accountID] {
                    transfer.toAccount = account
                } else {
                    transfer.toAccount = nil
                    skipped += 1
                }
            } else {
                transfer.toAccount = nil
            }
        }

        for backup in document.loans {
            guard let loan = loans[backup.id] else {
                continue
            }

            for entryID in backup.entryIDs {
                guard let entry = entries[entryID] else {
                    skipped += 1
                    continue
                }

                if entry.loan == nil {
                    entry.loan = loan
                }
            }
        }

        for backup in document.investmentCashFlows {
            guard let cashFlow = cashFlows[backup.id] else {
                continue
            }

            if let investmentID = backup.investmentID {
                if let investment = investments[investmentID] {
                    cashFlow.investment = investment
                } else {
                    cashFlow.investment = nil
                    skipped += 1
                }
            } else {
                cashFlow.investment = nil
            }

            if let entryID = backup.ledgerEntryID {
                if let entry = entries[entryID] {
                    cashFlow.ledgerEntry = entry
                } else {
                    cashFlow.ledgerEntry = nil
                    skipped += 1
                }
            }
        }

        for backup in document.envelopes {
            guard let envelope = envelopes[backup.id] else {
                continue
            }

            if let periodID = backup.periodID {
                if let period = periods[periodID] {
                    envelope.period = period
                } else {
                    envelope.period = nil
                    skipped += 1
                }
            } else {
                envelope.period = nil
            }

            if let categoryID = backup.categoryID {
                if let category = categories[categoryID] {
                    envelope.category = category
                } else {
                    envelope.category = nil
                    skipped += 1
                }
            } else {
                envelope.category = nil
            }
        }

        for backup in document.sinkingFunds {
            guard let fund = funds[backup.id] else {
                continue
            }

            if let categoryID = backup.categoryID {
                if let category = categories[categoryID] {
                    fund.category = category
                } else {
                    fund.category = nil
                    skipped += 1
                }
            } else {
                fund.category = nil
            }

            if let accountID = backup.accountID {
                if let account = accounts[accountID] {
                    fund.account = account
                } else {
                    fund.account = nil
                    skipped += 1
                }
            } else {
                fund.account = nil
            }
        }

        for backup in document.sinkingFundContributions {
            guard let contribution = contributions[backup.id] else {
                continue
            }

            if let fundID = backup.fundID {
                if let fund = funds[fundID] {
                    contribution.fund = fund
                } else {
                    contribution.fund = nil
                    skipped += 1
                }
            } else {
                contribution.fund = nil
            }

            if let accountID = backup.accountID {
                if let account = accounts[accountID] {
                    contribution.account = account
                } else {
                    contribution.account = nil
                    skipped += 1
                }
            } else {
                contribution.account = nil
            }
        }

        for backup in document.goals {
            guard let goal = goals[backup.id] else {
                continue
            }

            if let accountID = backup.accountID {
                if let account = accounts[accountID] {
                    goal.account = account
                } else {
                    goal.account = nil
                    skipped += 1
                }
            } else {
                goal.account = nil
            }
        }

        for backup in document.budgetAlerts {
            guard let alert = alerts[backup.id] else {
                continue
            }

            if let envelopeID = backup.envelopeID {
                if let envelope = envelopes[envelopeID] {
                    alert.envelope = envelope
                } else {
                    alert.envelope = nil
                    skipped += 1
                }
            } else {
                alert.envelope = nil
            }
        }

        try context.save()
        ManotiNotifications.postDataChanged()

        log("Restored \(inserted) inserted, \(updated) updated, \(skipped) skipped", level: .info)

        return RestoreSummary(inserted: inserted, updated: updated, skipped: skipped)
    }

    // MARK: - Scalar application

    private func apply(_ backup: BackupAppSettings, to settings: AppSettings) {
        settings.displayCurrencyCode = backup.displayCurrencyCode
        settings.weekStartsOn = backup.weekStartsOn
        settings.lockEnabled = backup.lockEnabled
        settings.lockAfterSeconds = backup.lockAfterSeconds
        settings.notificationsEnabled = backup.notificationsEnabled
        settings.dailyReminderEnabled = backup.dailyReminderEnabled
        settings.inboxReminderEnabled = backup.inboxReminderEnabled
        settings.weeklySummaryEnabled = backup.weeklySummaryEnabled
        settings.budgetAlertsEnabled = backup.budgetAlertsEnabled
        settings.largeTransactionAlertsEnabled = backup.largeTransactionAlertsEnabled
        settings.privacyModeEnabled = backup.privacyModeEnabled
        settings.largeTransactionThresholdMinor = backup.largeTransactionThresholdMinor
        // Scan dates and the last-backup timestamp describe this device, not the backup.
        // Restoring an old file must not reset or rewind them.
        settings.keepRawMessages = backup.keepRawMessages
        settings.reinvestmentRateBasisPoints = backup.reinvestmentRateBasisPoints
        settings.withholdingTaxBasisPoints = backup.withholdingTaxBasisPoints
    }

    private func apply(_ backup: BackupCategoryGroup, to group: CategoryGroup) {
        group.id = backup.id
        group.name = backup.name
        group.symbolName = backup.symbolName
        group.colorHex = backup.colorHex
        group.sortIndex = backup.sortIndex
        group.isArchived = backup.isArchived
        group.seedKey = backup.seedKey
    }

    private func apply(_ backup: BackupSpendingCategory, to category: SpendingCategory) {
        category.id = backup.id
        category.name = backup.name
        category.symbolName = backup.symbolName
        category.colorHex = backup.colorHex
        category.isFixed = backup.isFixed
        category.monthlyDefaultMinor = backup.monthlyDefaultMinor
        category.keywords = backup.keywords
        category.sortIndex = backup.sortIndex
        category.isArchived = backup.isArchived
        category.kind = CategoryKind(rawValue: backup.kindRaw ?? "") ?? .expense
    }

    private func apply(_ backup: BackupAccount, to account: Account) {
        account.id = backup.id
        account.name = backup.name
        account.kindRaw = backup.kindRaw
        account.currencyCode = backup.currencyCode
        account.colorHex = backup.colorHex
        account.symbolName = backup.symbolName
        account.institution = backup.institution
        account.note = backup.note
        account.isArchived = backup.isArchived
        account.sortIndex = backup.sortIndex
        account.createdAt = backup.createdAt
        account.updatedAt = backup.updatedAt
    }

    private func apply(_ backup: BackupAccountIdentifier, to identifier: AccountIdentifier) {
        identifier.id = backup.id
        identifier.value = backup.value
        identifier.typeRaw = backup.typeRaw
    }

    private func apply(_ backup: BackupMerchantMemory, to memory: MerchantMemory) {
        memory.id = backup.id
        memory.merchantKey = backup.merchantKey
        memory.displayName = backup.displayName
        memory.timesSeen = backup.timesSeen
        memory.lastSeenAt = backup.lastSeenAt
        memory.autoApply = backup.autoApply
        memory.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupMerchantAlias, to alias: MerchantAlias) {
        alias.id = backup.id
        alias.aliasKey = backup.aliasKey
    }

    private func apply(_ backup: BackupSmartRule, to rule: SmartRule) {
        rule.id = backup.id
        rule.name = backup.name
        rule.seedKey = backup.seedKey
        rule.isEnabled = backup.isEnabled
        rule.priority = backup.priority
        rule.conditionsJSON = backup.conditionsJSON
        rule.confidenceBoost = backup.confidenceBoost
        rule.timesApplied = backup.timesApplied
        rule.createdAt = backup.createdAt
        rule.updatedAt = backup.updatedAt
    }

    private func apply(_ backup: BackupParseRuleSet, to ruleSet: ParseRuleSet) {
        ruleSet.id = backup.id
        ruleSet.name = backup.name
        ruleSet.seedKey = backup.seedKey
        ruleSet.senderMatchers = backup.senderMatchers
        ruleSet.priority = backup.priority
        ruleSet.isEnabled = backup.isEnabled
        ruleSet.notes = backup.notes
    }

    private func apply(_ backup: BackupParseRule, to rule: ParseRule) {
        rule.id = backup.id
        rule.name = backup.name
        rule.messageTypeRaw = backup.messageTypeRaw
        rule.pattern = backup.pattern
        rule.fieldPatternsJSON = backup.fieldPatternsJSON
        rule.priority = backup.priority
        rule.isEnabled = backup.isEnabled
        rule.sampleText = backup.sampleText
    }

    private func apply(_ backup: BackupLedgerEntry, to entry: LedgerEntry) {
        entry.id = backup.id
        entry.occurredAt = backup.occurredAt
        entry.createdAt = backup.createdAt
        entry.kindRaw = backup.kindRaw
        entry.amountMinor = backup.amountMinor
        entry.feeMinor = backup.feeMinor
        entry.currencyCode = backup.currencyCode
        entry.payee = backup.payee
        entry.note = backup.note
        entry.sourceRaw = backup.sourceRaw
        entry.externalRef = backup.externalRef
        entry.counterpartRef = backup.counterpartRef
        entry.rawMessage = backup.rawMessage
        entry.messageSender = backup.messageSender
        entry.balanceAfterMinor = backup.balanceAfterMinor
        entry.statusRaw = backup.statusRaw
        entry.confidence = backup.confidence
        entry.dedupeHash = backup.dedupeHash
        entry.isSoftDeleted = backup.isSoftDeleted
    }

    private func apply(_ backup: BackupTransfer, to transfer: Transfer) {
        transfer.id = backup.id
        transfer.occurredAt = backup.occurredAt
        transfer.statusRaw = backup.statusRaw
        transfer.note = backup.note
        transfer.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupLoan, to loan: Loan) {
        loan.id = backup.id
        loan.directionRaw = backup.directionRaw
        loan.counterparty = backup.counterparty
        loan.principalMinor = backup.principalMinor
        loan.currencyCode = backup.currencyCode
        loan.startedAt = backup.startedAt
        loan.dueAt = backup.dueAt
        loan.note = backup.note
        loan.statusRaw = backup.statusRaw
        loan.createdAt = backup.createdAt
        loan.updatedAt = backup.updatedAt
        loan.isSoftDeleted = backup.isSoftDeleted
    }

    private func apply(_ backup: BackupInvestment, to investment: Investment) {
        investment.id = backup.id
        investment.typeRaw = backup.typeRaw
        investment.issueNumber = backup.issueNumber
        investment.isin = backup.isin
        investment.issuer = backup.issuer
        investment.nominalMinor = backup.nominalMinor
        investment.currencyCode = backup.currencyCode
        investment.couponRateBasisPoints = backup.couponRateBasisPoints.value
        investment.withholdingTaxBasisPoints = backup.withholdingTaxBasisPoints
        investment.taxExempt = backup.taxExempt
        investment.couponPeriodDays = backup.couponPeriodDays
        investment.issueDate = backup.issueDate
        investment.purchaseDate = backup.purchaseDate
        investment.settlementDate = backup.settlementDate
        investment.firstCouponDate = backup.firstCouponDate
        investment.maturityDate = backup.maturityDate
        investment.cleanPricePer100Scaled = backup.cleanPricePer100Scaled
        investment.accruedInterestMinor = backup.accruedInterestMinor
        investment.cashInvestedMinor = backup.cashInvestedMinor
        investment.accountID = backup.accountID
        investment.reinvestmentRateBasisPoints = backup.reinvestmentRateBasisPoints
        investment.note = backup.note
        investment.statusRaw = backup.statusRaw
        investment.isSoftDeleted = backup.isSoftDeleted
        investment.createdAt = backup.createdAt
        investment.updatedAt = backup.updatedAt
        investment.annualRateBasisPoints = backup.annualRateBasisPoints.value
        investment.compoundingRaw = backup.compoundingRaw
        investment.startDate = backup.startDate
        investment.marketValueMinor = backup.marketValueMinor
        investment.couponDateOverrides = backup.couponDateOverrides
    }

    private func apply(_ backup: BackupInvestmentCashFlow, to cashFlow: InvestmentCashFlow) {
        cashFlow.id = backup.id
        cashFlow.kindRaw = backup.kindRaw
        cashFlow.date = backup.date
        cashFlow.grossMinor = backup.grossMinor
        cashFlow.taxMinor = backup.taxMinor
        cashFlow.netMinor = backup.netMinor
        cashFlow.statusRaw = backup.statusRaw
        cashFlow.note = backup.note
        cashFlow.isSoftDeleted = backup.isSoftDeleted
        cashFlow.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupExchangeRate, to rate: ExchangeRateRecord) {
        rate.id = backup.id
        rate.baseCode = backup.baseCode
        rate.quoteCode = backup.quoteCode
        rate.rateScaled = backup.rateScaled
        rate.asOf = backup.asOf
        rate.sourceRaw = backup.sourceRaw
        rate.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupBudgetPeriod, to period: BudgetPeriod) {
        period.id = backup.id
        period.kindRaw = backup.kindRaw
        period.startDate = backup.startDate
        period.endDate = backup.endDate
        period.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupEnvelope, to envelope: Envelope) {
        envelope.id = backup.id
        envelope.limitMinor = backup.limitMinor
        envelope.currencyCode = backup.currencyCode
        envelope.rolloverEnabled = backup.rolloverEnabled
        envelope.note = backup.note
        envelope.isArchived = backup.isArchived
        envelope.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupSinkingFund, to fund: SinkingFund) {
        fund.id = backup.id
        fund.name = backup.name
        fund.targetMinor = backup.targetMinor
        fund.currencyCode = backup.currencyCode
        fund.monthlyAccrualMinor = backup.monthlyAccrualMinor
        fund.targetDate = backup.targetDate
        fund.note = backup.note
        fund.isArchived = backup.isArchived
        fund.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupSinkingFundContribution, to contribution: SinkingFundContribution) {
        contribution.id = backup.id
        contribution.amountMinor = backup.amountMinor
        contribution.occurredAt = backup.occurredAt
        contribution.note = backup.note
        contribution.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupGoal, to goal: Goal) {
        goal.id = backup.id
        goal.name = backup.name
        goal.targetMinor = backup.targetMinor
        goal.currencyCode = backup.currencyCode
        goal.targetDate = backup.targetDate
        goal.note = backup.note
        goal.isArchived = backup.isArchived
        goal.createdAt = backup.createdAt
    }

    private func apply(_ backup: BackupBudgetAlert, to alert: BudgetAlert) {
        alert.id = backup.id
        alert.thresholdPercent = backup.thresholdPercent
        alert.lastTriggeredPeriodStart = backup.lastTriggeredPeriodStart
        alert.createdAt = backup.createdAt
    }

    // MARK: - Helpers

    private func index<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) throws -> [UUID: T] {
        let rows = try context.fetch(FetchDescriptor<T>())
        return Dictionary(rows.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Returns `true` when the row was inserted, `false` when an existing row was updated.
    private func upsert<T: PersistentModel>(
        _ id: UUID,
        in index: inout [UUID: T],
        matching: ((T) -> Bool)? = nil,
        create: () -> T,
        apply: (T) -> Void
    ) -> Bool {
        if let existing = index[id] {
            apply(existing)
            return false
        }

        // A freshly installed store seeds its own UUIDs. Adopt the matching seeded row
        // instead of inserting a second copy of the whole taxonomy or rule set.
        if let matching, let existing = index.values.first(where: matching) {
            index[id] = existing
            apply(existing)
            return false
        }

        let row = create()
        apply(row)
        context.insert(row)
        index[id] = row
        return true
    }

    private func sortedByID<T>(_ rows: [T], id: (T) -> UUID) -> [T] {
        rows.sorted { id($0).uuidString < id($1).uuidString }
    }

    private func majorUnitString(minorUnits: Int64, exponent: Int) -> String {
        let negative = minorUnits < 0
        let magnitude = minorUnits.magnitude
        let sign = negative ? "-" : ""

        guard exponent > 0 else {
            return sign + String(magnitude)
        }

        var divisor: UInt64 = 1
        for _ in 0..<exponent {
            divisor *= 10
        }

        let whole = magnitude / divisor
        let fraction = magnitude % divisor
        let padded = String(fraction)
        let fractionText = String(repeating: "0", count: max(0, exponent - padded.count)) + padded
        return "\(sign)\(whole).\(fractionText)"
    }

    private func guardedCSVText(_ field: String) -> String {
        guard let first = field.first, "=+-@".contains(first) else {
            return field
        }

        return "'" + field
    }

    private func escapeCSV(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }

        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func dateStamp(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
