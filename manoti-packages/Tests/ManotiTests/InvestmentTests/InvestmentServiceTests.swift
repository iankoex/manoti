//
//  InvestmentServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("InvestmentService")
struct InvestmentServiceTests {
    private struct Services {
        let accounts: AccountService
        let investments: InvestmentService
        let insights: InsightsService
        let ledger: LedgerService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return Services(
            accounts: AccountService(context: context),
            investments: InvestmentService(context: context),
            insights: InsightsService(context: context),
            ledger: LedgerService(context: context),
            context: context
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        InvestmentMath.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @discardableResult
    private func createBond2019(
        _ services: Services,
        account: Account?,
        settlementDate: Date = InvestmentMath.calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 20)) ?? Date(),
        now: Date = InvestmentMath.calendar.date(from: DateComponents(year: 2026, month: 11, day: 21)) ?? Date()
    ) throws -> Investment {
        try services.investments.createBond(
            issueNumber: "FXD1/2019/015",
            isin: "KE5000009430",
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            firstCouponDate: date(2027, 1, 18),
            maturityDate: date(2034, 1, 9),
            purchaseDate: date(2026, 11, 20),
            settlementDate: settlementDate,
            cleanPrice: Decimal(string: "101.0567"),
            accruedInterestMinor: 222_525,
            cashInvestedMinor: 5_275_360,
            account: account,
            now: now
        )
    }

    @Test("A bond purchase moves cash into an asset")
    func purchaseIsNetWorthNeutral() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)

        let investment = try createBond2019(services, account: account)

        #expect(investment.status == .active)
        #expect(investment.cashInvestedMinor == 5_275_360)
        #expect(investment.accruedInterestMinor == 222_525)
        #expect(investment.cleanPricePer100Scaled == 1_010_567)
        #expect(account.balance.minorUnits == 4_724_640)

        let purchase = try #require(investment.cashFlows?.first)
        #expect(purchase.kind == .purchase)
        #expect(purchase.status == .paid)
        #expect(purchase.grossMinor == 5_275_360)
        #expect(purchase.ledgerEntry?.kind == .investmentOut)
        #expect(purchase.ledgerEntry?.amountMinor == 5_275_360)
        #expect(purchase.ledgerEntry?.account?.id == account.id)
        #expect(purchase.ledgerEntry?.signedAmountMinor == -5_275_360)
    }

    @Test("A pending settlement holds no cash and appears as pending")
    func pendingSettlement() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)

        let investment = try createBond2019(services, account: account, settlementDate: date(2026, 11, 23))

        #expect(investment.status == .pending)
        #expect(account.balance.minorUnits == 10_000_000)
        #expect(investment.cashFlows?.count == 1)
        #expect(investment.cashFlows?.first?.status == .pending)
        #expect(investment.cashFlows?.first?.ledgerEntry == nil)

        let summary = try services.investments.summary(displayCurrency: .kes, asOf: date(2026, 11, 21))
        #expect(summary.totalNominal.isZero)
        #expect(summary.cashInvested.isZero)
        #expect(summary.totalNetCoupons.isZero)
        #expect(summary.nextCoupon == nil)
        #expect(try services.investments.fetchInvestments().count == 1)
    }

    @Test("A pending settlement posts its cash once the date arrives, exactly once")
    func settlesPending() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)

        let investment = try createBond2019(services, account: account, settlementDate: date(2026, 11, 23))
        let cash = investment.cashInvestedMinor

        #expect(try services.investments.settlePendingInvestments(now: date(2026, 11, 22)) == 0)
        #expect(account.balance.minorUnits == 10_000_000)

        #expect(try services.investments.settlePendingInvestments(now: date(2026, 11, 24)) == 1)
        #expect(investment.status == .active)
        #expect(investment.cashFlows?.first?.status == .paid)
        #expect(investment.cashFlows?.first?.ledgerEntry?.kind == .investmentOut)
        #expect(account.balance.minorUnits == 10_000_000 - cash)

        #expect(try services.investments.settlePendingInvestments(now: date(2026, 11, 25)) == 0)
        #expect(account.balance.minorUnits == 10_000_000 - cash)
    }

    @Test("A coupon is income net of withholding tax, not an expense")
    func couponNetOfTax() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)
        let investment = try createBond2019(services, account: account)

        let flow = try services.investments.recordCoupon(
            investment,
            date: date(2027, 1, 18),
            grossMinor: 321_425,
            taxMinor: 32_142,
            note: "18 Jan 2027 coupon"
        )

        #expect(flow.kind == .coupon)
        #expect(flow.status == .paid)
        #expect(flow.grossMinor == 321_425)
        #expect(flow.taxMinor == 32_142)
        #expect(flow.netMinor == 289_283)
        #expect(flow.ledgerEntry?.kind == .investmentIncome)
        #expect(flow.ledgerEntry?.amountMinor == 289_283)
        #expect(account.balance.minorUnits == 5_013_923)

        let now = date(2027, 1, 19)
        let expenses = try services.insights.total(
            kind: .expense,
            from: now.addingTimeInterval(-172_800),
            to: now.addingTimeInterval(172_800),
            displayCurrency: .kes
        )
        #expect(expenses.amount.isZero)
    }

    @Test("A redemption returns cash and removes the asset")
    func redemption() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)
        let investment = try createBond2019(services, account: account)

        let flow = try services.investments.redeem(
            investment,
            date: date(2034, 1, 9),
            amountMinor: 5_000_000,
            account: account
        )

        #expect(investment.status == .matured)
        #expect(flow.kind == .redemption)
        #expect(flow.netMinor == 5_000_000)
        #expect(flow.ledgerEntry?.kind == .investmentIn)
        #expect(flow.ledgerEntry?.signedAmountMinor == 5_000_000)
        #expect(account.balance.minorUnits == 9_724_640)

        let summary = try services.investments.summary(displayCurrency: .kes, asOf: date(2034, 1, 10))
        #expect(summary.totalNominal.isZero)
        #expect(try services.investments.fetchInvestments(includeMatured: false).isEmpty)
    }

    @Test("A partial redemption stays active and cannot exceed the face value")
    func partialRedemption() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)
        let investment = try createBond2019(services, account: account)

        try services.investments.redeem(
            investment, date: date(2034, 1, 9), amountMinor: 2_000_000, account: account)
        #expect(investment.status == .active)

        #expect(throws: InvestmentError.invalidAmount) {
            try services.investments.redeem(
                investment, date: date(2034, 1, 10), amountMinor: 4_000_000, account: account)
        }

        try services.investments.redeem(
            investment, date: date(2034, 1, 11), amountMinor: 3_000_000, account: account)
        #expect(investment.status == .matured)
    }

    @Test("A redemption needs an account")
    func redemptionNeedsAccount() throws {
        let services = try makeServices()
        let investment = try createBond2019(services, account: nil)

        #expect(throws: InvestmentError.missingAccount) {
            try services.investments.redeem(
                investment, date: date(2034, 1, 9), amountMinor: 1_000_000)
        }
    }

    @Test("A money market account compounds daily at its after-tax rate")
    func moneyMarketDailyValue() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "MMA", kind: .bank, openingBalanceMinor: 10_000_000)

        let investment = try services.investments.createMoneyMarket(
            principalMinor: 10_000_000,
            annualRateBasisPoints: Decimal(1000),
            startDate: date(2025, 11, 21),
            withholdingTaxBasisPoints: 1000,
            account: account,
            now: date(2026, 11, 21)
        )

        #expect(investment.status == .active)
        #expect(account.balance.minorUnits == 0)
        #expect(investment.cashFlows?.first?.kind == .contribution)
        #expect(investment.currentValueMinor(asOf: date(2026, 11, 21)) == 10_941_621)

        let summary = try services.investments.summary(displayCurrency: .kes, asOf: date(2026, 11, 21))
        #expect(summary.totalNominal.minorUnits == 10_000_000)
        #expect(summary.cashInvested.minorUnits == 10_000_000)
        #expect(summary.nextCoupon == nil)
        #expect(summary.projectedValue.minorUnits == 10_941_621)
    }

    @Test("The summary aggregates active holdings and finds the next real coupon")
    func summaryRealPortfolio() throws {
        let services = try makeServices()
        let now = date(2026, 1, 1)

        try services.investments.createBond(
            issueNumber: "FXD1/2021/025",
            isin: "KE7000003652",
            nominalMinor: 15_000_000,
            couponRateBasisPoints: Decimal(string: "1392.4") ?? 0,
            firstCouponDate: date(2026, 11, 2),
            maturityDate: date(2046, 4, 9),
            purchaseDate: now,
            settlementDate: now,
            cashInvestedMinor: 15_000_000,
            now: now
        )
        try services.investments.createBond(
            issueNumber: "FXD1/2022/025",
            isin: "KE8000005093",
            nominalMinor: 10_000_000,
            couponRateBasisPoints: Decimal(string: "1418.8") ?? 0,
            firstCouponDate: date(2026, 10, 19),
            maturityDate: date(2047, 9, 23),
            purchaseDate: now,
            settlementDate: now,
            cashInvestedMinor: 10_000_000,
            now: now
        )

        let summary = try services.investments.summary(displayCurrency: .kes, asOf: date(2026, 11, 21))

        #expect(summary.totalNominal.minorUnits == 25_000_000)
        #expect(summary.cashInvested.minorUnits == 25_000_000)
        #expect(summary.totalNetCoupons.minorUnits == 63_470_250)
        #expect(
            summary.nextCoupon.map { InvestmentMath.calendar.isDate($0.date, inSameDayAs: date(2027, 4, 19)) } == true)
        #expect(summary.nextCoupon?.net.minorUnits == 638_460)
        #expect(summary.projectedValue.minorUnits > summary.cashInvested.minorUnits)
        #expect(summary.missingRates.isEmpty)
    }

    @Test("Schedule verification reports missing, mismatched and unexpected coupons")
    func verifySchedule() throws {
        let services = try makeServices()
        let investment = try services.investments.createBond(
            issueNumber: "FIXTURE",
            isin: "",
            nominalMinor: 10_000_000,
            couponRateBasisPoints: Decimal(1000),
            firstCouponDate: date(2027, 1, 1),
            maturityDate: date(2027, 7, 2),
            purchaseDate: date(2026, 12, 1),
            settlementDate: date(2026, 12, 1),
            cashInvestedMinor: 10_000_000,
            now: date(2026, 12, 2)
        )

        let beforeDue = services.investments.verifySchedule(investment, now: date(2026, 12, 2))
        #expect(beforeDue.isEmpty)

        try services.investments.recordCoupon(
            investment, date: date(2027, 1, 1), grossMinor: 500_000, taxMinor: 50_000)
        try services.investments.recordCoupon(
            investment, date: date(2027, 7, 2), grossMinor: 500_000, taxMinor: 60_000)

        let mismatched = services.investments.verifySchedule(investment, now: date(2027, 7, 3))
        #expect(mismatched.count == 1)
        #expect(mismatched.first?.kind == .amountMismatch)
        #expect(mismatched.first?.expectedNetMinor == 450_000)
        #expect(mismatched.first?.actualNetMinor == 440_000)

        try services.investments.recordCoupon(
            investment, date: date(2027, 3, 1), grossMinor: 500_000, taxMinor: 50_000)
        let unexpected = services.investments.verifySchedule(investment, now: date(2027, 7, 3))
        #expect(unexpected.contains { $0.kind == .unexpected })
    }

    @Test("Invalid amounts and archived accounts are rejected")
    func validation() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)

        #expect(throws: InvestmentError.invalidAmount) {
            try services.investments.createBond(
                issueNumber: "BAD",
                isin: "",
                nominalMinor: 0,
                couponRateBasisPoints: Decimal(1000),
                firstCouponDate: nil,
                maturityDate: nil
            )
        }

        try services.accounts.archive(account)

        #expect(throws: InvestmentError.archivedAccount) {
            try services.investments.createBond(
                issueNumber: "BAD",
                isin: "",
                nominalMinor: 100_000,
                couponRateBasisPoints: Decimal(1000),
                firstCouponDate: nil,
                maturityDate: nil,
                account: account
            )
        }
    }

    @Test("A repayment account must use the investment currency")
    func currencyMismatch() throws {
        let services = try makeServices()
        let kes = try services.accounts.create(name: "KES", kind: .bank, openingBalanceMinor: 10_000_000)
        let usd = try services.accounts.create(
            name: "USD", kind: .bank, currencyCode: "USD", openingBalanceMinor: 10_000)
        let investment = try createBond2019(services, account: kes)

        #expect(throws: InvestmentError.currencyMismatch) {
            try services.investments.redeem(
                investment, date: date(2034, 1, 9), amountMinor: 5_000_000, account: usd)
        }
    }

    @Test("A Treasury bill purchase is an asset, not spending")
    func treasuryBill() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)
        let now = date(2026, 1, 1)

        let bill = try services.investments.createTreasuryBill(
            nominalMinor: 1_000_000,
            purchasePriceMinor: 950_000,
            purchaseDate: now,
            maturityDate: date(2026, 10, 1),
            account: account,
            now: now
        )

        #expect(bill.type == .treasuryBill)
        #expect(bill.status == .active)
        #expect(bill.nominalMinor == 1_000_000)
        #expect(bill.cashInvestedMinor == 950_000)
        #expect(account.balance.minorUnits == 9_050_000)
        #expect(bill.cashFlows?.first?.ledgerEntry?.kind == .investmentOut)

        let expenses = try services.insights.total(
            kind: .expense,
            from: now.addingTimeInterval(-86_400),
            to: now.addingTimeInterval(86_400),
            displayCurrency: .kes
        )
        #expect(expenses.amount.isZero)
    }

    @Test("Deleting an investment reverses its cash and hides it from lists")
    func deleteInvestment() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa", kind: .mobileMoney, openingBalanceMinor: 10_000_000)
        let investment = try createBond2019(services, account: account)
        _ = try services.investments.recordCoupon(
            investment,
            date: date(2027, 1, 18),
            grossMinor: 321_425,
            taxMinor: 32_142
        )
        let flows = investment.cashFlows ?? []

        #expect(flows.count == 2)
        #expect(account.balance.minorUnits == 5_013_923)
        #expect(try services.investments.fetchInvestments().count == 1)

        try services.investments.delete(investment)

        #expect(investment.isSoftDeleted)
        #expect(flows.allSatisfy { $0.isSoftDeleted })
        #expect(flows.compactMap(\.ledgerEntry).allSatisfy { $0.isSoftDeleted })
        #expect(account.balance.minorUnits == 10_000_000)
        #expect(try services.investments.fetchInvestments(includeMatured: true).isEmpty)
    }

    @Test("The note can be edited without changing the recorded terms")
    func updateNote() throws {
        let services = try makeServices()
        let investment = try createBond2019(services, account: nil)

        try services.investments.updateNote(investment, note: "  corrected note  ")

        #expect(investment.note == "corrected note")
        #expect(investment.nominalMinor == 5_000_000)
        #expect(investment.cashInvestedMinor == 5_275_360)
    }
}
