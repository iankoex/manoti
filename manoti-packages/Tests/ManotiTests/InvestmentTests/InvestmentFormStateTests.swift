//
//  InvestmentFormStateTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices
@testable import InvestmentsFeature

@MainActor
@Suite("Investment forms")
struct InvestmentFormStateTests {
    private struct Services {
        let accounts: AccountService
        let investments: InvestmentService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        return Services(
            accounts: AccountService(context: context),
            investments: InvestmentService(context: context),
            context: context
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        InvestmentMath.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func makeBondForm() -> InvestmentFormState {
        let state = InvestmentFormState(mode: .bond)
        state.nominalText = "150,000"
        state.couponRateText = "13.924"
        state.purchaseDate = date(2026, 11, 21)
        state.firstCouponDate = date(2027, 5, 3)
        state.maturityDate = date(2046, 4, 9)
        state.cleanPriceText = "101.0567"
        state.accruedInterestText = "2,225.25"
        return state
    }

    @Test("A comma-decimal rate is read as a decimal, not dropped")
    func commaDecimalRate() throws {
        let state = InvestmentFormState(mode: .bond)
        state.withholdingTaxText = "7,5"

        #expect(state.withholdingTaxBasisPoints == 750)
    }

    @Test("A bill defaults to a short maturity")
    func billMaturity() throws {
        let state = InvestmentFormState(mode: .bill)
        let maturity = try #require(state.maturityDate)
        let days = InvestmentMath.calendar.dateComponents(
            [.day], from: state.purchaseDate, to: maturity
        ).day

        #expect(days == 364)
        #expect(state.firstCouponDate == nil)
    }

    @Test("A first coupon before the purchase date cannot save")
    func firstCouponBeforePurchase() throws {
        let state = makeBondForm()
        state.firstCouponDate = date(2026, 1, 1)

        #expect(!state.canSave)
        #expect(state.validationMessages.contains { $0.contains("first coupon") })
    }

    @Test("An empty form cannot be saved")
    func emptyFormCannotSave() throws {
        let state = InvestmentFormState()

        #expect(state.canSave == false)
        #expect(!state.validationMessages.isEmpty)
    }

    @Test("A nominal-only bond uses the prefilled defaults and saves")
    func nominalOnlyBondDefaults() throws {
        let services = try makeServices()

        let state = InvestmentFormState(mode: .bond)
        state.nominalText = "100,000"

        #expect(state.couponRateBasisPoints == Decimal(1200))
        #expect(state.withholdingTaxBasisPoints == 1000)
        #expect(state.cleanPricePer100 == Decimal(100))
        #expect(state.canSave)

        let investment = try state.save(investmentService: services.investments)

        #expect(investment.type == .treasuryBond)
        #expect(investment.nominalMinor == 10_000_000)
        #expect(investment.couponRateBasisPoints == Decimal(1200))
        #expect(investment.withholdingTaxBasisPoints == 1000)
        #expect(investment.cleanPricePer100Scaled == 1_000_000)
        #expect(investment.cashInvestedMinor == 10_000_000)
        #expect(investment.firstCouponDate != nil)
        #expect(investment.maturityDate != nil)
    }

    @Test("A bond form parses three-decimal coupons and the dirty price")
    func bondDirtyPrice() throws {
        let state = makeBondForm()

        #expect(state.canSave)
        #expect(state.couponRateBasisPoints == Decimal(string: "1392.4"))
        #expect(state.accruedInterestMinor == 222_525)
        #expect(state.dirtyPrice?.minorUnits == 15_381_030)
    }

    @Test("Saving a bond records clean price, accrued interest and dirty cash")
    func saveBond() throws {
        let services = try makeServices()
        let account = try services.accounts.create(
            name: "M-Pesa",
            kind: .mobileMoney,
            openingBalanceMinor: 50_000_000
        )
        let state = makeBondForm()
        state.issueNumber = " FXD1/2021/025 "
        state.isin = "KE7000003652"
        state.reload(accountService: services.accounts)
        state.selectedAccountID = account.id
        state.reinvestmentRateText = "12.5"
        state.note = "  First lot  "

        let investment = try state.save(investmentService: services.investments)

        #expect(investment.type == .treasuryBond)
        #expect(investment.issueNumber == "FXD1/2021/025")
        #expect(investment.nominalMinor == 15_000_000)
        #expect(investment.couponRateBasisPoints == Decimal(string: "1392.4"))
        #expect(investment.cleanPricePer100Scaled == 1_010_567)
        #expect(investment.accruedInterestMinor == 222_525)
        #expect(investment.cashInvestedMinor == 15_381_030)
        #expect(investment.reinvestmentRateBasisPoints == 1250)
        #expect(investment.note == "First lot")
        #expect(investment.accountID == account.id)
        #expect(account.balance.minorUnits == 34_618_970)
    }

    @Test("An explicit cash invested amount wins over the computed dirty price")
    func explicitCashInvested() throws {
        let services = try makeServices()
        let state = makeBondForm()
        state.cashInvestedText = "153,810.30"

        let investment = try state.save(investmentService: services.investments)

        #expect(investment.cashInvestedMinor == 15_381_030)
    }

    @Test("Invalid dates and rates block the bond form")
    func invalidBondInput() {
        let state = makeBondForm()
        state.maturityDate = date(2020, 1, 1)

        #expect(!state.canSave)
        #expect(state.validationMessages.contains { $0.contains("Maturity") })

        state.maturityDate = date(2046, 4, 9)
        state.couponRateText = "150"
        #expect(!state.canSave)
        #expect(state.validationMessages.contains { $0.contains("coupon rate") })

        state.couponRateText = "13.924"
        state.withholdingTaxText = "not a rate"
        #expect(!state.canSave)
        #expect(state.validationMessages.contains { $0.contains("withholding") })
    }

    @Test("A bill needs a price below nominal and a later maturity")
    func billValidation() throws {
        let services = try makeServices()
        let state = InvestmentFormState(mode: .bill)
        state.nominalText = "100,000"
        state.purchasePriceText = "95,000"
        state.purchaseDate = date(2027, 1, 4)
        state.maturityDate = date(2027, 4, 4)

        #expect(state.canSave)

        let bill = try state.save(investmentService: services.investments)
        #expect(bill.type == .treasuryBill)
        #expect(bill.nominalMinor == 10_000_000)
        #expect(bill.cashInvestedMinor == 9_500_000)

        state.purchasePriceText = "101,000"
        #expect(!state.canSave)
        #expect(state.validationMessages.contains { $0.contains("less than its nominal") })

        state.purchasePriceText = "95,000"
        state.maturityDate = date(2026, 12, 1)
        #expect(!state.canSave)
    }

    @Test("A money market account needs a principal and annual rate")
    func moneyMarketValidation() throws {
        let services = try makeServices()

        let state = InvestmentFormState(mode: .moneyMarket)
        #expect(!state.canSave)

        state.principalText = "50,000"
        state.annualRateText = "10"
        state.startDate = date(2027, 1, 1)

        #expect(state.canSave)

        let account = try state.save(investmentService: services.investments)
        #expect(account.type == .moneyMarket)
        #expect(account.nominalMinor == 5_000_000)
        #expect(account.annualRateBasisPoints == 1000)
    }

    @Test("A tax-exempt investment stores the exemption")
    func taxExempt() throws {
        let services = try makeServices()
        let state = makeBondForm()
        state.taxExempt = true

        let investment = try state.save(investmentService: services.investments)

        #expect(investment.taxExempt)
        #expect(investment.effectiveWithholdingTaxBasisPoints == 0)
    }

    @Test("A non-KES account is rejected before saving")
    func nonKesAccount() throws {
        let services = try makeServices()
        _ = try services.accounts.create(
            name: "Dollar account",
            kind: .bank,
            currencyCode: "USD",
            openingBalanceMinor: 10_000
        )
        let state = makeBondForm()
        state.reload(accountService: services.accounts)

        #expect(state.selectedAccount?.currencyCode == "USD")
        #expect(!state.canSave)
        #expect(state.validationMessages.contains { $0.contains("KES") })
    }

    @Test("The form reloads active accounts and selects the first one")
    func accountReload() throws {
        let services = try makeServices()
        let first = try services.accounts.create(
            name: "M-Pesa",
            kind: .mobileMoney,
            openingBalanceMinor: 0
        )
        _ = try services.accounts.create(name: "Bank", kind: .bank, openingBalanceMinor: 0)

        let state = InvestmentFormState()
        state.reload(accountService: services.accounts)

        #expect(state.activeAccounts.count == 2)
        #expect(state.selectedAccount?.id == first.id)
    }
}
