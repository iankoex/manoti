//
//  BackupDocument.swift
//  AppModels
//

import CryptoKit
import Foundation

/// A JSON backup of all user-owned rows.
///
/// Relationships are stored as UUIDs and every amount is a minor-unit `Int64`, so a backup
/// can be restored into a fresh store without depending on SwiftData's internal identities.
/// Dates use ISO-8601 with fractional seconds; `Decimal` values are strings so no binary
/// floating-point conversion ever happens.
nonisolated public struct BackupDocument: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// SHA-256 of the document encoded with this field empty. Optional so backups written
    /// before checksums existed still restore.
    public var checksum: String?
    public var exportedAt: Date
    public var appVersion: String
    public var settings: BackupAppSettings?
    public var categoryGroups: [BackupCategoryGroup]
    public var categories: [BackupSpendingCategory]
    public var accounts: [BackupAccount]
    public var accountIdentifiers: [BackupAccountIdentifier]
    public var merchantMemories: [BackupMerchantMemory]
    public var merchantAliases: [BackupMerchantAlias]
    /// Optional so backups written before inbox learning still decode.
    public var ingestMemories: [BackupIngestMemory]?
    public var smartRules: [BackupSmartRule]
    public var parseRuleSets: [BackupParseRuleSet]
    public var parseRules: [BackupParseRule]
    public var ledgerEntries: [BackupLedgerEntry]
    public var transfers: [BackupTransfer]
    public var loans: [BackupLoan]
    public var investments: [BackupInvestment]
    public var investmentCashFlows: [BackupInvestmentCashFlow]
    public var exchangeRates: [BackupExchangeRate]
    public var budgetPeriods: [BackupBudgetPeriod]
    public var envelopes: [BackupEnvelope]
    public var sinkingFunds: [BackupSinkingFund]
    public var sinkingFundContributions: [BackupSinkingFundContribution]
    public var goals: [BackupGoal]
    public var budgetAlerts: [BackupBudgetAlert]

    public init(
        schemaVersion: Int,
        exportedAt: Date,
        appVersion: String,
        settings: BackupAppSettings?,
        categoryGroups: [BackupCategoryGroup],
        categories: [BackupSpendingCategory],
        accounts: [BackupAccount],
        accountIdentifiers: [BackupAccountIdentifier],
        merchantMemories: [BackupMerchantMemory],
        merchantAliases: [BackupMerchantAlias],
        ingestMemories: [BackupIngestMemory]? = nil,
        smartRules: [BackupSmartRule],
        parseRuleSets: [BackupParseRuleSet],
        parseRules: [BackupParseRule],
        ledgerEntries: [BackupLedgerEntry],
        transfers: [BackupTransfer],
        loans: [BackupLoan],
        investments: [BackupInvestment],
        investmentCashFlows: [BackupInvestmentCashFlow],
        exchangeRates: [BackupExchangeRate],
        budgetPeriods: [BackupBudgetPeriod],
        envelopes: [BackupEnvelope],
        sinkingFunds: [BackupSinkingFund],
        sinkingFundContributions: [BackupSinkingFundContribution],
        goals: [BackupGoal],
        budgetAlerts: [BackupBudgetAlert],
        checksum: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.checksum = checksum
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.settings = settings
        self.categoryGroups = categoryGroups
        self.categories = categories
        self.accounts = accounts
        self.accountIdentifiers = accountIdentifiers
        self.merchantMemories = merchantMemories
        self.merchantAliases = merchantAliases
        self.ingestMemories = ingestMemories
        self.smartRules = smartRules
        self.parseRuleSets = parseRuleSets
        self.parseRules = parseRules
        self.ledgerEntries = ledgerEntries
        self.transfers = transfers
        self.loans = loans
        self.investments = investments
        self.investmentCashFlows = investmentCashFlows
        self.exchangeRates = exchangeRates
        self.budgetPeriods = budgetPeriods
        self.envelopes = envelopes
        self.sinkingFunds = sinkingFunds
        self.sinkingFundContributions = sinkingFundContributions
        self.goals = goals
        self.budgetAlerts = budgetAlerts
    }
}

nonisolated public enum BackupChecksum {
    /// Stable checksum over the document's contents, excluding the checksum field itself.
    public static func value(for document: BackupDocument) throws -> String {
        var copy = document
        copy.checksum = nil
        let data = try BackupCoding.encoder().encode(copy)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A `Decimal` encoded as a string, preserving every significant digit.
nonisolated public struct BackupDecimal: Codable, Hashable, Sendable {
    public var value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)

        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal string, found \(text)"
            )
        }

        self.value = decimal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(value)")
    }
}

/// JSON coding configured for stable, exact backups.
nonisolated public enum BackupCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)

            if let date = fractionalFormatter().date(from: text) ?? plainFormatter().date(from: text) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date, found \(text)"
            )
        }
        return decoder
    }

    /// ISO-8601 in UTC with fractional seconds, the shape used by both backup and CSV.
    public static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

nonisolated public struct BackupAppSettings: Codable, Sendable {
    public var id: UUID
    public var displayCurrencyCode: String
    public var weekStartsOn: Int
    public var lockEnabled: Bool
    public var lockAfterSeconds: Int
    public var notificationsEnabled: Bool
    public var dailyReminderEnabled: Bool
    public var inboxReminderEnabled: Bool
    public var weeklySummaryEnabled: Bool
    public var budgetAlertsEnabled: Bool
    public var largeTransactionAlertsEnabled: Bool
    public var privacyModeEnabled: Bool
    public var largeTransactionThresholdMinor: Int64
    public var lastNotificationScanAt: Date?
    public var keepRawMessages: Bool
    public var lastBackupAt: Date?
    public var reinvestmentRateBasisPoints: Int
    public var withholdingTaxBasisPoints: Int

    public init(
        id: UUID,
        displayCurrencyCode: String,
        weekStartsOn: Int,
        lockEnabled: Bool,
        lockAfterSeconds: Int,
        notificationsEnabled: Bool,
        dailyReminderEnabled: Bool,
        inboxReminderEnabled: Bool,
        weeklySummaryEnabled: Bool,
        budgetAlertsEnabled: Bool,
        largeTransactionAlertsEnabled: Bool,
        privacyModeEnabled: Bool,
        largeTransactionThresholdMinor: Int64,
        lastNotificationScanAt: Date?,
        keepRawMessages: Bool,
        lastBackupAt: Date?,
        reinvestmentRateBasisPoints: Int,
        withholdingTaxBasisPoints: Int
    ) {
        self.id = id
        self.displayCurrencyCode = displayCurrencyCode
        self.weekStartsOn = weekStartsOn
        self.lockEnabled = lockEnabled
        self.lockAfterSeconds = lockAfterSeconds
        self.notificationsEnabled = notificationsEnabled
        self.dailyReminderEnabled = dailyReminderEnabled
        self.inboxReminderEnabled = inboxReminderEnabled
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.budgetAlertsEnabled = budgetAlertsEnabled
        self.largeTransactionAlertsEnabled = largeTransactionAlertsEnabled
        self.privacyModeEnabled = privacyModeEnabled
        self.largeTransactionThresholdMinor = largeTransactionThresholdMinor
        self.lastNotificationScanAt = lastNotificationScanAt
        self.keepRawMessages = keepRawMessages
        self.lastBackupAt = lastBackupAt
        self.reinvestmentRateBasisPoints = reinvestmentRateBasisPoints
        self.withholdingTaxBasisPoints = withholdingTaxBasisPoints
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayCurrencyCode
        case weekStartsOn
        case lockEnabled
        case lockAfterSeconds
        case notificationsEnabled
        case dailyReminderEnabled
        case inboxReminderEnabled
        case weeklySummaryEnabled
        case budgetAlertsEnabled
        case largeTransactionAlertsEnabled
        case privacyModeEnabled
        case largeTransactionThresholdMinor
        case lastNotificationScanAt
        case keepRawMessages
        case lastBackupAt
        case reinvestmentRateBasisPoints
        case withholdingTaxBasisPoints
    }

    /// Backups written before the notification flags existed decode with the same defaults a
    /// fresh install uses, so an older file remains restorable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayCurrencyCode = try container.decode(String.self, forKey: .displayCurrencyCode)
        weekStartsOn = try container.decode(Int.self, forKey: .weekStartsOn)
        lockEnabled = try container.decode(Bool.self, forKey: .lockEnabled)
        lockAfterSeconds = try container.decode(Int.self, forKey: .lockAfterSeconds)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        dailyReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyReminderEnabled) ?? true
        inboxReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .inboxReminderEnabled) ?? true
        weeklySummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklySummaryEnabled) ?? true
        budgetAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .budgetAlertsEnabled) ?? true
        largeTransactionAlertsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .largeTransactionAlertsEnabled) ?? true
        privacyModeEnabled = try container.decode(Bool.self, forKey: .privacyModeEnabled)
        largeTransactionThresholdMinor = try container.decode(Int64.self, forKey: .largeTransactionThresholdMinor)
        lastNotificationScanAt = try container.decodeIfPresent(Date.self, forKey: .lastNotificationScanAt)
        keepRawMessages = try container.decode(Bool.self, forKey: .keepRawMessages)
        lastBackupAt = try container.decodeIfPresent(Date.self, forKey: .lastBackupAt)
        reinvestmentRateBasisPoints = try container.decode(Int.self, forKey: .reinvestmentRateBasisPoints)
        withholdingTaxBasisPoints = try container.decode(Int.self, forKey: .withholdingTaxBasisPoints)
    }
}

nonisolated public struct BackupCategoryGroup: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var sortIndex: Int
    public var isArchived: Bool
    public var seedKey: String

    public init(
        id: UUID,
        name: String,
        symbolName: String,
        colorHex: String,
        sortIndex: Int,
        isArchived: Bool,
        seedKey: String
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.isArchived = isArchived
        self.seedKey = seedKey
    }
}

nonisolated public struct BackupSpendingCategory: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var isFixed: Bool
    public var monthlyDefaultMinor: Int64?
    public var keywords: String
    public var sortIndex: Int
    public var isArchived: Bool
    public var groupID: UUID?
    public var kindRaw: String?

    public init(
        id: UUID,
        name: String,
        symbolName: String,
        colorHex: String,
        isFixed: Bool,
        monthlyDefaultMinor: Int64?,
        keywords: String,
        sortIndex: Int,
        isArchived: Bool,
        groupID: UUID?,
        kindRaw: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.isFixed = isFixed
        self.monthlyDefaultMinor = monthlyDefaultMinor
        self.keywords = keywords
        self.sortIndex = sortIndex
        self.isArchived = isArchived
        self.groupID = groupID
        self.kindRaw = kindRaw
    }
}

nonisolated public struct BackupAccount: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kindRaw: String
    public var currencyCode: String
    public var colorHex: String
    public var symbolName: String
    public var institution: String
    public var note: String
    public var isArchived: Bool
    public var sortIndex: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        kindRaw: String,
        currencyCode: String,
        colorHex: String,
        symbolName: String,
        institution: String,
        note: String,
        isArchived: Bool,
        sortIndex: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.currencyCode = currencyCode
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.institution = institution
        self.note = note
        self.isArchived = isArchived
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated public struct BackupAccountIdentifier: Codable, Sendable {
    public var id: UUID
    public var value: String
    public var typeRaw: String
    public var accountID: UUID?

    public init(id: UUID, value: String, typeRaw: String, accountID: UUID?) {
        self.id = id
        self.value = value
        self.typeRaw = typeRaw
        self.accountID = accountID
    }
}

nonisolated public struct BackupMerchantMemory: Codable, Sendable {
    public var id: UUID
    public var merchantKey: String
    public var displayName: String
    public var categoryID: UUID?
    public var accountID: UUID?
    public var timesSeen: Int
    public var lastSeenAt: Date
    public var autoApply: Bool
    public var createdAt: Date
    /// Optional so backups written before per-category counts still decode.
    public var categoryCountsJSON: String?

    public init(
        id: UUID,
        merchantKey: String,
        displayName: String,
        categoryID: UUID?,
        accountID: UUID?,
        timesSeen: Int,
        lastSeenAt: Date,
        autoApply: Bool,
        createdAt: Date,
        categoryCountsJSON: String? = nil
    ) {
        self.id = id
        self.merchantKey = merchantKey
        self.displayName = displayName
        self.categoryID = categoryID
        self.accountID = accountID
        self.timesSeen = timesSeen
        self.lastSeenAt = lastSeenAt
        self.autoApply = autoApply
        self.createdAt = createdAt
        self.categoryCountsJSON = categoryCountsJSON
    }
}

nonisolated public struct BackupMerchantAlias: Codable, Sendable {
    public var id: UUID
    public var aliasKey: String
    public var merchantMemoryID: UUID?

    public init(id: UUID, aliasKey: String, merchantMemoryID: UUID?) {
        self.id = id
        self.aliasKey = aliasKey
        self.merchantMemoryID = merchantMemoryID
    }
}

nonisolated public struct BackupSmartRule: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var seedKey: String
    public var isEnabled: Bool
    public var priority: Int
    public var conditionsJSON: String
    public var targetCategoryID: UUID?
    public var confidenceBoost: Double
    public var timesApplied: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        seedKey: String,
        isEnabled: Bool,
        priority: Int,
        conditionsJSON: String,
        targetCategoryID: UUID?,
        confidenceBoost: Double,
        timesApplied: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.seedKey = seedKey
        self.isEnabled = isEnabled
        self.priority = priority
        self.conditionsJSON = conditionsJSON
        self.targetCategoryID = targetCategoryID
        self.confidenceBoost = confidenceBoost
        self.timesApplied = timesApplied
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated public struct BackupParseRuleSet: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var seedKey: String
    public var senderMatchers: String
    public var priority: Int
    public var isEnabled: Bool
    public var notes: String

    public init(
        id: UUID,
        name: String,
        seedKey: String,
        senderMatchers: String,
        priority: Int,
        isEnabled: Bool,
        notes: String
    ) {
        self.id = id
        self.name = name
        self.seedKey = seedKey
        self.senderMatchers = senderMatchers
        self.priority = priority
        self.isEnabled = isEnabled
        self.notes = notes
    }
}

nonisolated public struct BackupParseRule: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var messageTypeRaw: String
    public var pattern: String
    public var fieldPatternsJSON: String
    public var priority: Int
    public var isEnabled: Bool
    public var sampleText: String
    public var ruleSetID: UUID?

    public init(
        id: UUID,
        name: String,
        messageTypeRaw: String,
        pattern: String,
        fieldPatternsJSON: String,
        priority: Int,
        isEnabled: Bool,
        sampleText: String,
        ruleSetID: UUID?
    ) {
        self.id = id
        self.name = name
        self.messageTypeRaw = messageTypeRaw
        self.pattern = pattern
        self.fieldPatternsJSON = fieldPatternsJSON
        self.priority = priority
        self.isEnabled = isEnabled
        self.sampleText = sampleText
        self.ruleSetID = ruleSetID
    }
}

nonisolated public struct BackupLedgerEntry: Codable, Sendable {
    public var id: UUID
    public var occurredAt: Date
    public var createdAt: Date
    public var kindRaw: String
    public var amountMinor: Int64
    public var feeMinor: Int64
    public var currencyCode: String
    public var accountID: UUID?
    public var categoryID: UUID?
    public var payee: String
    public var note: String
    public var sourceRaw: String
    public var externalRef: String
    public var counterpartRef: String
    public var rawMessage: String
    public var messageSender: String
    public var balanceAfterMinor: Int64?
    public var statusRaw: String
    public var confidence: Double
    public var dedupeHash: String
    public var isSoftDeleted: Bool
    public var transferID: UUID?
    public var loanID: UUID?
    public var investmentCashFlowID: UUID?
    /// Optional so backups written before fingerprints still decode.
    public var ingestFingerprint: String?

    public init(
        id: UUID,
        occurredAt: Date,
        createdAt: Date,
        kindRaw: String,
        amountMinor: Int64,
        feeMinor: Int64,
        currencyCode: String,
        accountID: UUID?,
        categoryID: UUID?,
        payee: String,
        note: String,
        sourceRaw: String,
        externalRef: String,
        counterpartRef: String,
        rawMessage: String,
        messageSender: String,
        balanceAfterMinor: Int64?,
        statusRaw: String,
        confidence: Double,
        dedupeHash: String,
        isSoftDeleted: Bool,
        transferID: UUID?,
        loanID: UUID?,
        investmentCashFlowID: UUID?,
        ingestFingerprint: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.kindRaw = kindRaw
        self.amountMinor = amountMinor
        self.feeMinor = feeMinor
        self.currencyCode = currencyCode
        self.accountID = accountID
        self.categoryID = categoryID
        self.payee = payee
        self.note = note
        self.sourceRaw = sourceRaw
        self.externalRef = externalRef
        self.counterpartRef = counterpartRef
        self.rawMessage = rawMessage
        self.messageSender = messageSender
        self.balanceAfterMinor = balanceAfterMinor
        self.statusRaw = statusRaw
        self.confidence = confidence
        self.dedupeHash = dedupeHash
        self.isSoftDeleted = isSoftDeleted
        self.transferID = transferID
        self.loanID = loanID
        self.investmentCashFlowID = investmentCashFlowID
        self.ingestFingerprint = ingestFingerprint
    }
}

nonisolated public struct BackupTransfer: Codable, Sendable {
    public var id: UUID
    public var occurredAt: Date
    public var statusRaw: String
    public var note: String
    public var createdAt: Date
    public var fromAccountID: UUID?
    public var toAccountID: UUID?

    public init(
        id: UUID,
        occurredAt: Date,
        statusRaw: String,
        note: String,
        createdAt: Date,
        fromAccountID: UUID?,
        toAccountID: UUID?
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.statusRaw = statusRaw
        self.note = note
        self.createdAt = createdAt
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
    }
}

nonisolated public struct BackupLoan: Codable, Sendable {
    public var id: UUID
    public var directionRaw: String
    public var counterparty: String
    public var principalMinor: Int64
    public var currencyCode: String
    public var startedAt: Date
    public var dueAt: Date?
    public var note: String
    public var statusRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isSoftDeleted: Bool
    public var entryIDs: [UUID]

    public init(
        id: UUID,
        directionRaw: String,
        counterparty: String,
        principalMinor: Int64,
        currencyCode: String,
        startedAt: Date,
        dueAt: Date?,
        note: String,
        statusRaw: String,
        createdAt: Date,
        updatedAt: Date,
        isSoftDeleted: Bool,
        entryIDs: [UUID]
    ) {
        self.id = id
        self.directionRaw = directionRaw
        self.counterparty = counterparty
        self.principalMinor = principalMinor
        self.currencyCode = currencyCode
        self.startedAt = startedAt
        self.dueAt = dueAt
        self.note = note
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSoftDeleted = isSoftDeleted
        self.entryIDs = entryIDs
    }
}

nonisolated public struct BackupInvestment: Codable, Sendable {
    public var id: UUID
    public var typeRaw: String
    public var issueNumber: String
    public var isin: String
    public var issuer: String
    public var nominalMinor: Int64
    public var currencyCode: String
    public var couponRateBasisPoints: BackupDecimal
    public var withholdingTaxBasisPoints: Int
    public var taxExempt: Bool
    public var couponPeriodDays: Int
    public var issueDate: Date?
    public var purchaseDate: Date
    public var settlementDate: Date?
    public var firstCouponDate: Date?
    public var maturityDate: Date?
    public var cleanPricePer100Scaled: Int64?
    public var accruedInterestMinor: Int64
    public var cashInvestedMinor: Int64
    public var accountID: UUID?
    public var reinvestmentRateBasisPoints: Int?
    public var note: String
    public var statusRaw: String
    public var isSoftDeleted: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var annualRateBasisPoints: BackupDecimal
    public var compoundingRaw: String
    public var startDate: Date?
    public var marketValueMinor: Int64?
    public var couponDateOverrides: [Date]

    public init(
        id: UUID,
        typeRaw: String,
        issueNumber: String,
        isin: String,
        issuer: String,
        nominalMinor: Int64,
        currencyCode: String,
        couponRateBasisPoints: BackupDecimal,
        withholdingTaxBasisPoints: Int,
        taxExempt: Bool,
        couponPeriodDays: Int,
        issueDate: Date?,
        purchaseDate: Date,
        settlementDate: Date?,
        firstCouponDate: Date?,
        maturityDate: Date?,
        cleanPricePer100Scaled: Int64?,
        accruedInterestMinor: Int64,
        cashInvestedMinor: Int64,
        accountID: UUID?,
        reinvestmentRateBasisPoints: Int?,
        note: String,
        statusRaw: String,
        isSoftDeleted: Bool,
        createdAt: Date,
        updatedAt: Date,
        annualRateBasisPoints: BackupDecimal,
        compoundingRaw: String,
        startDate: Date?,
        marketValueMinor: Int64?,
        couponDateOverrides: [Date]
    ) {
        self.id = id
        self.typeRaw = typeRaw
        self.issueNumber = issueNumber
        self.isin = isin
        self.issuer = issuer
        self.nominalMinor = nominalMinor
        self.currencyCode = currencyCode
        self.couponRateBasisPoints = couponRateBasisPoints
        self.withholdingTaxBasisPoints = withholdingTaxBasisPoints
        self.taxExempt = taxExempt
        self.couponPeriodDays = couponPeriodDays
        self.issueDate = issueDate
        self.purchaseDate = purchaseDate
        self.settlementDate = settlementDate
        self.firstCouponDate = firstCouponDate
        self.maturityDate = maturityDate
        self.cleanPricePer100Scaled = cleanPricePer100Scaled
        self.accruedInterestMinor = accruedInterestMinor
        self.cashInvestedMinor = cashInvestedMinor
        self.accountID = accountID
        self.reinvestmentRateBasisPoints = reinvestmentRateBasisPoints
        self.note = note
        self.statusRaw = statusRaw
        self.isSoftDeleted = isSoftDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.annualRateBasisPoints = annualRateBasisPoints
        self.compoundingRaw = compoundingRaw
        self.startDate = startDate
        self.marketValueMinor = marketValueMinor
        self.couponDateOverrides = couponDateOverrides
    }
}

nonisolated public struct BackupInvestmentCashFlow: Codable, Sendable {
    public var id: UUID
    public var kindRaw: String
    public var date: Date
    public var grossMinor: Int64
    public var taxMinor: Int64
    public var netMinor: Int64
    public var statusRaw: String
    public var note: String
    public var isSoftDeleted: Bool
    public var createdAt: Date
    public var investmentID: UUID?
    public var ledgerEntryID: UUID?

    public init(
        id: UUID,
        kindRaw: String,
        date: Date,
        grossMinor: Int64,
        taxMinor: Int64,
        netMinor: Int64,
        statusRaw: String,
        note: String,
        isSoftDeleted: Bool,
        createdAt: Date,
        investmentID: UUID?,
        ledgerEntryID: UUID?
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.date = date
        self.grossMinor = grossMinor
        self.taxMinor = taxMinor
        self.netMinor = netMinor
        self.statusRaw = statusRaw
        self.note = note
        self.isSoftDeleted = isSoftDeleted
        self.createdAt = createdAt
        self.investmentID = investmentID
        self.ledgerEntryID = ledgerEntryID
    }
}

nonisolated public struct BackupExchangeRate: Codable, Sendable {
    public var id: UUID
    public var baseCode: String
    public var quoteCode: String
    public var rateScaled: Int64
    public var asOf: Date
    public var sourceRaw: String
    public var createdAt: Date

    public init(
        id: UUID,
        baseCode: String,
        quoteCode: String,
        rateScaled: Int64,
        asOf: Date,
        sourceRaw: String,
        createdAt: Date
    ) {
        self.id = id
        self.baseCode = baseCode
        self.quoteCode = quoteCode
        self.rateScaled = rateScaled
        self.asOf = asOf
        self.sourceRaw = sourceRaw
        self.createdAt = createdAt
    }
}

nonisolated public struct BackupBudgetPeriod: Codable, Sendable {
    public var id: UUID
    public var kindRaw: String
    public var startDate: Date
    public var endDate: Date
    public var createdAt: Date

    public init(id: UUID, kindRaw: String, startDate: Date, endDate: Date, createdAt: Date) {
        self.id = id
        self.kindRaw = kindRaw
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }
}

nonisolated public struct BackupEnvelope: Codable, Sendable {
    public var id: UUID
    public var limitMinor: Int64
    public var currencyCode: String
    public var rolloverEnabled: Bool
    public var note: String
    public var isArchived: Bool
    public var createdAt: Date
    public var periodID: UUID?
    public var categoryID: UUID?

    public init(
        id: UUID,
        limitMinor: Int64,
        currencyCode: String,
        rolloverEnabled: Bool,
        note: String,
        isArchived: Bool,
        createdAt: Date,
        periodID: UUID?,
        categoryID: UUID?
    ) {
        self.id = id
        self.limitMinor = limitMinor
        self.currencyCode = currencyCode
        self.rolloverEnabled = rolloverEnabled
        self.note = note
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.periodID = periodID
        self.categoryID = categoryID
    }
}

nonisolated public struct BackupSinkingFund: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var targetMinor: Int64
    public var currencyCode: String
    public var monthlyAccrualMinor: Int64
    public var targetDate: Date?
    public var note: String
    public var isArchived: Bool
    public var createdAt: Date
    public var categoryID: UUID?
    public var accountID: UUID?

    public init(
        id: UUID,
        name: String,
        targetMinor: Int64,
        currencyCode: String,
        monthlyAccrualMinor: Int64,
        targetDate: Date?,
        note: String,
        isArchived: Bool,
        createdAt: Date,
        categoryID: UUID?,
        accountID: UUID?
    ) {
        self.id = id
        self.name = name
        self.targetMinor = targetMinor
        self.currencyCode = currencyCode
        self.monthlyAccrualMinor = monthlyAccrualMinor
        self.targetDate = targetDate
        self.note = note
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.categoryID = categoryID
        self.accountID = accountID
    }
}

nonisolated public struct BackupSinkingFundContribution: Codable, Sendable {
    public var id: UUID
    public var amountMinor: Int64
    public var occurredAt: Date
    public var note: String
    public var createdAt: Date
    public var fundID: UUID?
    public var accountID: UUID?

    public init(
        id: UUID,
        amountMinor: Int64,
        occurredAt: Date,
        note: String,
        createdAt: Date,
        fundID: UUID?,
        accountID: UUID?
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.occurredAt = occurredAt
        self.note = note
        self.createdAt = createdAt
        self.fundID = fundID
        self.accountID = accountID
    }
}

nonisolated public struct BackupGoal: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var targetMinor: Int64
    public var currencyCode: String
    public var targetDate: Date?
    public var note: String
    public var isArchived: Bool
    public var createdAt: Date
    public var accountID: UUID?

    public init(
        id: UUID,
        name: String,
        targetMinor: Int64,
        currencyCode: String,
        targetDate: Date?,
        note: String,
        isArchived: Bool,
        createdAt: Date,
        accountID: UUID?
    ) {
        self.id = id
        self.name = name
        self.targetMinor = targetMinor
        self.currencyCode = currencyCode
        self.targetDate = targetDate
        self.note = note
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.accountID = accountID
    }
}

nonisolated public struct BackupBudgetAlert: Codable, Sendable {
    public var id: UUID
    public var thresholdPercent: Int
    public var lastTriggeredPeriodStart: Date?
    public var createdAt: Date
    public var envelopeID: UUID?

    public init(
        id: UUID,
        thresholdPercent: Int,
        lastTriggeredPeriodStart: Date?,
        createdAt: Date,
        envelopeID: UUID?
    ) {
        self.id = id
        self.thresholdPercent = thresholdPercent
        self.lastTriggeredPeriodStart = lastTriggeredPeriodStart
        self.createdAt = createdAt
        self.envelopeID = envelopeID
    }
}

nonisolated public struct BackupIngestMemory: Codable, Sendable {
    public var id: UUID
    public var sender: String
    public var fingerprint: String
    public var reasonRaw: String
    public var amountMinor: Int64
    public var kindRaw: String
    public var externalRef: String
    public var hitCount: Int
    public var lastSeenAt: Date
    public var createdAt: Date

    public init(
        id: UUID,
        sender: String,
        fingerprint: String,
        reasonRaw: String,
        amountMinor: Int64,
        kindRaw: String,
        externalRef: String,
        hitCount: Int,
        lastSeenAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.sender = sender
        self.fingerprint = fingerprint
        self.reasonRaw = reasonRaw
        self.amountMinor = amountMinor
        self.kindRaw = kindRaw
        self.externalRef = externalRef
        self.hitCount = hitCount
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
    }
}
