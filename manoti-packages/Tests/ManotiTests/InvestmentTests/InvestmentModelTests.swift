//
//  InvestmentModelTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels

@MainActor
@Suite("Investment models")
struct InvestmentModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(inMemory: true)
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        InvestmentMath.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @Test("An investment round-trips with its terms and cash flows")
    func roundTrip() throws {
        let context = try makeContext()
        let accountID = UUID()
        let investment = Investment(
            type: .treasuryBond,
            issueNumber: "FXD1/2019/015",
            isin: "KE5000009430",
            issuer: "CBK",
            nominalMinor: 5_000_000,
            couponRateBasisPoints: Decimal(string: "1285.7") ?? 0,
            withholdingTaxBasisPoints: 1000,
            purchaseDate: date(2026, 11, 23),
            settlementDate: date(2026, 11, 23),
            firstCouponDate: date(2027, 1, 18),
            maturityDate: date(2034, 1, 9),
            cleanPricePer100Scaled: 1_010_567,
            accruedInterestMinor: 222_525,
            cashInvestedMinor: 5_275_360,
            accountID: accountID,
            status: .active
        )
        context.insert(investment)

        let flow = InvestmentCashFlow(
            kind: .purchase,
            date: date(2026, 11, 23),
            grossMinor: 5_275_360,
            taxMinor: 0,
            status: .paid
        )
        flow.investment = investment
        context.insert(flow)

        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Investment>()).first
        let fetchedFlow = try context.fetch(FetchDescriptor<InvestmentCashFlow>()).first

        #expect(fetched?.issueNumber == "FXD1/2019/015")
        #expect(fetched?.couponRateBasisPoints == Decimal(string: "1285.7"))
        #expect(fetched?.nominalMinor == 5_000_000)
        #expect(fetched?.cashInvestedMinor == 5_275_360)
        #expect(fetched?.accruedInterestMinor == 222_525)
        #expect(fetched?.cleanPricePer100Scaled == 1_010_567)
        #expect(fetched?.accountID == accountID)
        #expect(fetched?.status == .active)
        #expect(fetched?.cashFlows?.count == 1)
        #expect(fetchedFlow?.investment?.id == fetched?.id)
        #expect(fetchedFlow?.netMinor == 5_275_360)
    }

    @Test("A cash flow's ledger entry points back through its inverse")
    func ledgerEntryInverse() throws {
        let context = try makeContext()
        let investment = Investment(type: .treasuryBond, nominalMinor: 100_000)
        context.insert(investment)

        let entry = LedgerEntry(kind: .investmentIncome, amountMinor: 9_000)
        context.insert(entry)

        let flow = InvestmentCashFlow(kind: .coupon, grossMinor: 10_000, taxMinor: 1_000, status: .paid)
        flow.investment = investment
        flow.ledgerEntry = entry
        context.insert(flow)
        try context.save()

        #expect(entry.investmentCashFlow?.id == flow.id)
        #expect(flow.ledgerEntry?.id == entry.id)
    }

    @Test("Investment enums carry display names and symbols")
    func enumMetadata() {
        #expect(InvestmentType.moneyMarket.displayName == "Money market")
        #expect(InvestmentType.treasuryBond.symbolName == "doc.text")
        #expect(InvestmentStatus.pending.displayName == "Pending settlement")
        #expect(InvestmentCashFlowKind.coupon.displayName == "Coupon")
        #expect(InvestmentCashFlowKind.withdrawal.symbolName == "minus.circle")
        #expect(InvestmentCashFlowStatus.paid.displayName == "Paid")
    }

    @Test("Settings default to 12% reinvestment and 10% withholding")
    func settingsDefaults() throws {
        let settings = AppSettings()

        #expect(settings.reinvestmentRateBasisPoints == 1200)
        #expect(settings.withholdingTaxBasisPoints == 1000)
        #expect(AppSettings.defaultReinvestmentRateBasisPoints == 1200)
        #expect(AppSettings.defaultWithholdingTaxBasisPoints == 1000)
    }

    @Test("Settings round-trip edited investment defaults")
    func settingsRoundTrip() throws {
        let context = try makeContext()
        let settings = AppSettings()
        settings.reinvestmentRateBasisPoints = 1500
        settings.withholdingTaxBasisPoints = 500
        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppSettings>()).first
        #expect(fetched?.reinvestmentRateBasisPoints == 1500)
        #expect(fetched?.withholdingTaxBasisPoints == 500)
    }

    @Test("Investment ledger kinds sign the account balance correctly")
    func ledgerEntrySigns() {
        let out = LedgerEntry(kind: .investmentOut, amountMinor: 5_275_360, feeMinor: 100)
        #expect(out.signedAmountMinor == -5_275_460)

        let inbound = LedgerEntry(kind: .investmentIn, amountMinor: 5_000_000, feeMinor: 100)
        #expect(inbound.signedAmountMinor == 4_999_900)

        let income = LedgerEntry(kind: .investmentIncome, amountMinor: 289_283, feeMinor: 0)
        #expect(income.signedAmountMinor == 289_283)

        #expect(LedgerEntryKind.investmentOut.displayName == "Investment purchase")
        #expect(LedgerEntryKind.investmentIn.displayName == "Investment redemption")
        #expect(LedgerEntryKind.investmentIncome.displayName == "Investment income")
        #expect(LedgerEntryKind.investmentOut.symbolName == "chart.line.uptrend.xyaxis")
    }

    @Test("Investment kinds are not spending, but coupon income counts as income")
    func spendingAndIncomeFlags() {
        for kind in [LedgerEntryKind.investmentOut, .investmentIn] {
            #expect(!kind.countsAsSpending)
            #expect(!kind.countsAsIncome)
        }

        #expect(!LedgerEntryKind.investmentIncome.countsAsSpending)
        #expect(LedgerEntryKind.investmentIncome.countsAsIncome)
        #expect(LedgerEntryKind.investmentIncome.isInvestmentLeg)
    }

    @Test("Only active rows have a current value")
    func currentValueStatus() {
        let pending = Investment(
            type: .treasuryBond, nominalMinor: 100_000, cashInvestedMinor: 100_000, status: .pending)
        let matured = Investment(
            type: .treasuryBond, nominalMinor: 100_000, cashInvestedMinor: 100_000, status: .matured)
        let active = Investment(type: .treasuryBond, nominalMinor: 100_000, cashInvestedMinor: 98_000, status: .active)

        #expect(pending.currentValueMinor() == 0)
        #expect(matured.currentValueMinor() == 0)
        #expect(active.currentValueMinor() == 98_000)
    }
}
