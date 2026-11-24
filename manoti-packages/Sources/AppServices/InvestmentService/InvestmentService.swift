//
//  InvestmentService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

public enum InvestmentError: Error, Equatable {
    case invalidAmount
    case invalidRate
    case invalidDates
    case archivedAccount
    case currencyMismatch
    case notActive
    case invalidCoupon
    case missingAccount
}

extension InvestmentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .invalidAmount: return "Enter an amount greater than zero."
            case .invalidRate: return "Enter a valid rate."
            case .invalidDates: return "Check the investment dates."
            case .archivedAccount: return "That account is archived."
            case .currencyMismatch: return "The account and investment use different currencies."
            case .notActive: return "This investment is no longer active."
            case .invalidCoupon: return "Enter a coupon greater than zero with tax no higher than the coupon."
            case .missingAccount: return "Link an account before redeeming."
        }
    }
}

/// Creates bonds, bills and money market accounts, records coupons and redemptions, and
/// verifies coupon schedules.
///
/// Every cash movement is an ordinary `LedgerEntry`, so account balances stay the single
/// source of truth. Purchases and redemptions are asset transfers, not spending; coupons
/// are income net of withholding tax.
@Observable
nonisolated public final class InvestmentService: Loggable {
    let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Creation

    @discardableResult
    public func createBond(
        issueNumber: String,
        isin: String,
        nominalMinor: Int64,
        couponRateBasisPoints: Decimal,
        firstCouponDate: Date?,
        maturityDate: Date?,
        purchaseDate: Date = Date(),
        settlementDate: Date? = nil,
        issueDate: Date? = nil,
        withholdingTaxBasisPoints: Int = AppSettings.defaultWithholdingTaxBasisPoints,
        taxExempt: Bool = false,
        cleanPrice: Decimal? = nil,
        accruedInterestMinor: Int64 = 0,
        cashInvestedMinor: Int64? = nil,
        account: Account? = nil,
        reinvestmentRateBasisPoints: Int? = nil,
        couponDateOverrides: [Date] = [],
        note: String = "",
        now: Date = Date()
    ) throws -> Investment {
        guard nominalMinor > 0 else {
            throw InvestmentError.invalidAmount
        }

        guard couponRateBasisPoints >= 0 else {
            throw InvestmentError.invalidRate
        }

        guard accruedInterestMinor >= 0, (cashInvestedMinor ?? 0) >= 0 else {
            throw InvestmentError.invalidAmount
        }

        if let firstCouponDate, let maturityDate, firstCouponDate > maturityDate {
            throw InvestmentError.invalidDates
        }

        try validate(account: account, currencyCode: CurrencyCatalog.defaultCurrency.code)

        let cleanPriceMinor = cleanPrice.map {
            InvestmentMath.cleanPriceMinor(nominalMinor: nominalMinor, pricePer100: $0)
        }
        let dirtyPrice = InvestmentMath.dirtyPriceMinor(
            cleanPriceMinor: cleanPriceMinor ?? nominalMinor,
            accruedInterestMinor: accruedInterestMinor
        )
        let cashInvested = cashInvestedMinor ?? dirtyPrice
        let settlement = settlementDate ?? purchaseDate
        let pending = settlement > now
        let investment = Investment(
            type: .treasuryBond,
            issueNumber: issueNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            isin: isin.trimmingCharacters(in: .whitespacesAndNewlines),
            issuer: "CBK",
            nominalMinor: nominalMinor,
            couponRateBasisPoints: couponRateBasisPoints,
            withholdingTaxBasisPoints: withholdingTaxBasisPoints,
            taxExempt: taxExempt,
            issueDate: issueDate,
            purchaseDate: purchaseDate,
            settlementDate: settlementDate,
            firstCouponDate: firstCouponDate,
            maturityDate: maturityDate,
            cleanPricePer100Scaled: cleanPrice.map(InvestmentMath.scaledCleanPrice),
            accruedInterestMinor: accruedInterestMinor,
            cashInvestedMinor: cashInvested,
            accountID: account?.id,
            reinvestmentRateBasisPoints: reinvestmentRateBasisPoints,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            status: pending ? .pending : .active,
            couponDateOverrides: couponDateOverrides.sorted()
        )
        context.insert(investment)

        recordPurchase(
            investment: investment,
            amountMinor: cashInvested,
            date: settlement,
            status: pending ? .pending : .paid,
            kind: .purchase,
            account: pending ? nil : account
        )

        try commit()
        log("Created bond \(investment.issueNumber) for \(nominalMinor) minor units", level: .info)
        return investment
    }

    @discardableResult
    public func createTreasuryBill(
        nominalMinor: Int64,
        purchasePriceMinor: Int64,
        purchaseDate: Date = Date(),
        maturityDate: Date,
        withholdingTaxBasisPoints: Int = AppSettings.defaultWithholdingTaxBasisPoints,
        taxExempt: Bool = false,
        account: Account? = nil,
        note: String = "",
        now: Date = Date()
    ) throws -> Investment {
        guard nominalMinor > 0, purchasePriceMinor > 0 else {
            throw InvestmentError.invalidAmount
        }

        guard purchaseDate <= maturityDate else {
            throw InvestmentError.invalidDates
        }

        try validate(account: account, currencyCode: CurrencyCatalog.defaultCurrency.code)

        let pending = purchaseDate > now
        let investment = Investment(
            type: .treasuryBill,
            issueNumber: "",
            isin: "",
            issuer: "CBK",
            nominalMinor: nominalMinor,
            couponRateBasisPoints: 0,
            withholdingTaxBasisPoints: withholdingTaxBasisPoints,
            taxExempt: taxExempt,
            purchaseDate: purchaseDate,
            maturityDate: maturityDate,
            cashInvestedMinor: purchasePriceMinor,
            accountID: account?.id,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            status: pending ? .pending : .active
        )
        context.insert(investment)

        recordPurchase(
            investment: investment,
            amountMinor: purchasePriceMinor,
            date: purchaseDate,
            status: pending ? .pending : .paid,
            kind: .purchase,
            account: pending ? nil : account
        )

        try commit()
        log("Created Treasury bill for \(nominalMinor) minor units", level: .info)
        return investment
    }

    @discardableResult
    public func createMoneyMarket(
        principalMinor: Int64,
        annualRateBasisPoints: Decimal,
        startDate: Date = Date(),
        withholdingTaxBasisPoints: Int = AppSettings.defaultWithholdingTaxBasisPoints,
        taxExempt: Bool = false,
        account: Account? = nil,
        note: String = "",
        now: Date = Date()
    ) throws -> Investment {
        guard principalMinor > 0 else {
            throw InvestmentError.invalidAmount
        }

        guard annualRateBasisPoints >= 0 else {
            throw InvestmentError.invalidRate
        }

        try validate(account: account, currencyCode: CurrencyCatalog.defaultCurrency.code)

        let pending = startDate > now
        let investment = Investment(
            type: .moneyMarket,
            issueNumber: "Money market",
            issuer: "",
            nominalMinor: principalMinor,
            couponRateBasisPoints: 0,
            withholdingTaxBasisPoints: withholdingTaxBasisPoints,
            taxExempt: taxExempt,
            purchaseDate: startDate,
            cashInvestedMinor: principalMinor,
            accountID: account?.id,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            status: pending ? .pending : .active,
            annualRateBasisPoints: annualRateBasisPoints,
            startDate: startDate
        )
        context.insert(investment)

        recordPurchase(
            investment: investment,
            amountMinor: principalMinor,
            date: startDate,
            status: pending ? .pending : .paid,
            kind: .contribution,
            account: pending ? nil : account
        )

        try commit()
        log("Created money market account for \(principalMinor) minor units", level: .info)
        return investment
    }

    // MARK: - Settlement

    /// Promotes pending purchases whose settlement date has arrived and posts the deferred
    /// cash movement once. Safe to call on every launch.
    @discardableResult
    public func settlePendingInvestments(now: Date = Date()) throws -> Int {
        let pendingRaw = InvestmentStatus.pending.rawValue
        let investments = try context.fetch(
            FetchDescriptor<Investment>(
                predicate: #Predicate<Investment> {
                    $0.statusRaw == pendingRaw && !$0.isSoftDeleted
                }
            )
        )

        var settled = 0

        for investment in investments {
            let settlement = investment.settlementDate ?? investment.purchaseDate
            guard settlement <= now else {
                continue
            }

            let account = try linkedAccount(for: investment)

            for flow in (investment.cashFlows ?? [])
            where flow.kind == .purchase && flow.status == .pending {
                flow.status = .paid

                if let account, flow.ledgerEntry == nil {
                    let entry = LedgerEntry(
                        kind: .investmentOut,
                        amountMinor: flow.netMinor,
                        currencyCode: investment.currencyCode,
                        occurredAt: flow.date,
                        payee: investment.issueNumber,
                        note: investment.note
                    )
                    entry.account = account
                    context.insert(entry)
                    flow.ledgerEntry = entry
                }
            }

            investment.status = .active
            settled += 1
        }

        if settled > 0 {
            try context.save()
            ManotiNotifications.postDataChanged()
        }

        return settled
    }

    // MARK: - Coupons

    @discardableResult
    public func recordCoupon(
        _ investment: Investment,
        date: Date,
        grossMinor: Int64,
        taxMinor: Int64,
        note: String = ""
    ) throws -> InvestmentCashFlow {
        guard investment.status == .active else {
            throw InvestmentError.notActive
        }

        guard grossMinor > 0, taxMinor >= 0, taxMinor <= grossMinor else {
            throw InvestmentError.invalidCoupon
        }

        let netMinor = grossMinor - taxMinor
        let flow = InvestmentCashFlow(
            kind: .coupon,
            date: date,
            grossMinor: grossMinor,
            taxMinor: taxMinor,
            netMinor: netMinor,
            status: .paid,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        flow.investment = investment
        context.insert(flow)

        if let account = try linkedAccount(for: investment) {
            try validate(account: account, currencyCode: investment.currencyCode)
            let entry = LedgerEntry(
                kind: .investmentIncome,
                amountMinor: netMinor,
                currencyCode: investment.currencyCode,
                occurredAt: date,
                payee: investment.issueNumber,
                note: flow.note
            )
            entry.account = account
            context.insert(entry)
            flow.ledgerEntry = entry
        }

        investment.updatedAt = Date()
        append(flow, to: investment)
        try commit()
        log("Recorded coupon of \(netMinor) minor units net for \(investment.issueNumber)", level: .info)
        return flow
    }

    /// Compares paid coupon rows with the expected schedule.
    ///
    /// Dates match by calendar day.
    public func verifySchedule(_ investment: Investment, now: Date = Date()) -> [ScheduleMismatch] {
        let expected = InvestmentMath.couponSchedule(for: investment, from: investment.purchaseDate)
            .filter { $0.date <= now }
        let paid = (investment.cashFlows ?? [])
            .filter { $0.kind == .coupon && $0.status == .paid && !$0.isSoftDeleted }
            .sorted { $0.date < $1.date }

        var unmatched = paid
        var mismatches: [ScheduleMismatch] = []

        for entry in expected {
            if let index = unmatched.firstIndex(where: {
                InvestmentMath.calendar.isDate($0.date, inSameDayAs: entry.date)
            }) {
                let flow = unmatched.remove(at: index)
                if flow.netMinor != entry.netMinor {
                    mismatches.append(
                        ScheduleMismatch(
                            kind: .amountMismatch,
                            expectedDate: entry.date,
                            actualDate: flow.date,
                            expectedNetMinor: entry.netMinor,
                            actualNetMinor: flow.netMinor
                        )
                    )
                }
            } else {
                mismatches.append(
                    ScheduleMismatch(
                        kind: .missing,
                        expectedDate: entry.date,
                        expectedNetMinor: entry.netMinor
                    )
                )
            }
        }

        for flow in unmatched {
            mismatches.append(
                ScheduleMismatch(
                    kind: .unexpected,
                    actualDate: flow.date,
                    actualNetMinor: flow.netMinor
                )
            )
        }

        return mismatches
    }

    // MARK: - Redemption

    @discardableResult
    public func redeem(
        _ investment: Investment,
        date: Date,
        amountMinor: Int64,
        account: Account? = nil,
        note: String = ""
    ) throws -> InvestmentCashFlow {
        guard investment.status == .active else {
            throw InvestmentError.notActive
        }

        guard amountMinor > 0 else {
            throw InvestmentError.invalidAmount
        }

        let redeemed =
            (investment.cashFlows ?? [])
            .filter { $0.kind == .redemption && !$0.isSoftDeleted }
            .reduce(Int64(0)) { $0 + $1.netMinor }
        let remaining = max(0, investment.nominalMinor - redeemed)
        guard amountMinor <= remaining else {
            throw InvestmentError.invalidAmount
        }

        let target: Account?
        if let account {
            target = account
        } else {
            target = try linkedAccount(for: investment)
        }

        guard let target else {
            throw InvestmentError.missingAccount
        }

        try validate(account: target, currencyCode: investment.currencyCode)

        let flow = InvestmentCashFlow(
            kind: .redemption,
            date: date,
            grossMinor: amountMinor,
            taxMinor: 0,
            netMinor: amountMinor,
            status: .paid,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        flow.investment = investment
        context.insert(flow)

        let entry = LedgerEntry(
            kind: .investmentIn,
            amountMinor: amountMinor,
            currencyCode: investment.currencyCode,
            occurredAt: date,
            payee: investment.issueNumber,
            note: flow.note
        )
        entry.account = target
        context.insert(entry)
        flow.ledgerEntry = entry

        investment.status = redeemed + amountMinor >= investment.nominalMinor ? .matured : .active
        investment.updatedAt = Date()
        append(flow, to: investment)
        try commit()
        log("Redeemed \(investment.issueNumber) for \(amountMinor) minor units", level: .info)
        return flow
    }

    // MARK: - Editing

    /// Updates the free-form note without touching the recorded terms.
    public func updateNote(_ investment: Investment, note: String) throws {
        guard !investment.isSoftDeleted else {
            return
        }

        investment.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        investment.updatedAt = Date()
        try commit()
        log("Updated note for \(investment.issueNumber)", level: .info)
    }

    /// Soft-deletes the holding, every cash flow and the linked ledger entries.
    ///
    /// Ledger entries remain in the store for recovery, but account balances exclude them,
    /// so a deleted purchase reverses the cash the same way the original purchase moved it.
    public func delete(_ investment: Investment) throws {
        guard !investment.isSoftDeleted else {
            return
        }

        investment.isSoftDeleted = true
        investment.updatedAt = Date()

        for flow in investment.cashFlows ?? [] where !flow.isSoftDeleted {
            flow.isSoftDeleted = true

            if let entry = flow.ledgerEntry, !entry.isSoftDeleted {
                entry.isSoftDeleted = true
            }
        }

        try commit()
        log("Deleted investment \(investment.issueNumber)", level: .info)
    }

    // MARK: - Fetch

    public func fetchInvestments(includeMatured: Bool = true) throws -> [Investment] {
        var descriptor = FetchDescriptor<Investment>(
            sortBy: [
                SortDescriptor(\Investment.purchaseDate, order: .reverse),
                SortDescriptor(\Investment.createdAt, order: .reverse),
            ]
        )

        if includeMatured {
            descriptor.predicate = #Predicate<Investment> { !$0.isSoftDeleted }
        } else {
            descriptor.predicate = #Predicate<Investment> {
                !$0.isSoftDeleted && $0.statusRaw != "matured"
            }
        }

        return try context.fetch(descriptor)
    }

    public func fetchInvestment(id: UUID) throws -> Investment? {
        var descriptor = FetchDescriptor<Investment>(predicate: #Predicate<Investment> { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Private

    private func recordPurchase(
        investment: Investment,
        amountMinor: Int64,
        date: Date,
        status: InvestmentCashFlowStatus,
        kind: InvestmentCashFlowKind,
        account: Account?
    ) {
        let flow = InvestmentCashFlow(
            kind: kind,
            date: date,
            grossMinor: amountMinor,
            taxMinor: 0,
            netMinor: amountMinor,
            status: status,
            note: investment.note
        )
        flow.investment = investment
        context.insert(flow)

        if let account {
            let entry = LedgerEntry(
                kind: .investmentOut,
                amountMinor: amountMinor,
                currencyCode: investment.currencyCode,
                occurredAt: date,
                payee: investment.issueNumber,
                note: investment.note
            )
            entry.account = account
            context.insert(entry)
            flow.ledgerEntry = entry
        }

        append(flow, to: investment)
    }

    private func append(_ flow: InvestmentCashFlow, to investment: Investment) {
        var flows = investment.cashFlows ?? []
        if !flows.contains(where: { $0.id == flow.id }) {
            flows.append(flow)
        }
        investment.cashFlows = flows
    }

    private func linkedAccount(for investment: Investment) throws -> Account? {
        guard let accountID = investment.accountID else {
            return nil
        }

        var descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == accountID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func validate(account: Account?, currencyCode: String) throws {
        guard let account else {
            return
        }

        guard !account.isArchived else {
            throw InvestmentError.archivedAccount
        }

        guard account.currencyCode == currencyCode else {
            throw InvestmentError.currencyMismatch
        }
    }

    private func commit() throws {
        try context.save()
        ManotiNotifications.postDataChanged()
    }
}
