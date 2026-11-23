//
//  Investment.swift
//  AppModels
//

import Foundation
import SwiftData

/// A bond, Treasury bill or money market account.
///
/// Cash movements are ordinary `LedgerEntry` rows linked through `InvestmentCashFlow`, so
/// account balances remain the single source of truth. A purchase is not spending, a
/// redemption is not income, and coupons are income net of withholding tax.
///
/// The linked cash account is stored as `accountID` rather than as a SwiftData relationship.
/// A relationship here would need an inverse on `Account`; keeping the identifier makes the
/// model CloudKit-safe without widening the account schema. Resolve it through the purchase
/// cash flow's ledger entry or `AccountService` when a screen needs the account row.
@Model
public final class Investment {
    public var id: UUID = UUID()
    public var typeRaw: String = InvestmentType.treasuryBond.rawValue
    public var issueNumber: String = ""
    public var isin: String = ""
    public var issuer: String = ""
    public var nominalMinor: Int64 = 0
    public var currencyCode: String = CurrencyCatalog.defaultCurrency.code

    /// The annual coupon rate in basis points. `Decimal` keeps three-decimal CBK rates such
    /// as 12.857% exact; whole-point rates such as 12% are 1200.
    public var couponRateBasisPoints: Decimal = 0
    public var withholdingTaxBasisPoints: Int = AppSettings.defaultWithholdingTaxBasisPoints
    public var taxExempt: Bool = false
    public var couponPeriodDays: Int = InvestmentMath.defaultCouponPeriodDays

    public var issueDate: Date?
    public var purchaseDate: Date = Date()
    public var settlementDate: Date?
    public var firstCouponDate: Date?
    public var maturityDate: Date?

    /// Clean price per 100 nominal, scaled by `InvestmentMath.cleanPriceScale` (10,000).
    public var cleanPricePer100Scaled: Int64?
    public var accruedInterestMinor: Int64 = 0
    public var cashInvestedMinor: Int64 = 0

    public var accountID: UUID?
    public var reinvestmentRateBasisPoints: Int?
    public var note: String = ""
    public var statusRaw: String = InvestmentStatus.active.rawValue
    public var isSoftDeleted: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    /// Money market terms.
    public var annualRateBasisPoints: Decimal = 0
    public var compoundingRaw: String = InvestmentCompounding.daily.rawValue
    public var startDate: Date?

    /// A user-supplied market value.
    ///
    /// Bonds use the cost basis until this is set.
    public var marketValueMinor: Int64?

    /// Exact prospectus coupon dates.
    ///
    /// When non-empty this is the authoritative schedule and the 182-day generator is not
    /// used.
    public var couponDateOverrides: [Date] = []

    @Relationship(deleteRule: .cascade, inverse: \InvestmentCashFlow.investment)
    public var cashFlows: [InvestmentCashFlow]?

    public init(
        type: InvestmentType,
        issueNumber: String = "",
        isin: String = "",
        issuer: String = "",
        nominalMinor: Int64 = 0,
        currencyCode: String = CurrencyCatalog.defaultCurrency.code,
        couponRateBasisPoints: Decimal = 0,
        withholdingTaxBasisPoints: Int = AppSettings.defaultWithholdingTaxBasisPoints,
        taxExempt: Bool = false,
        couponPeriodDays: Int = InvestmentMath.defaultCouponPeriodDays,
        issueDate: Date? = nil,
        purchaseDate: Date = Date(),
        settlementDate: Date? = nil,
        firstCouponDate: Date? = nil,
        maturityDate: Date? = nil,
        cleanPricePer100Scaled: Int64? = nil,
        accruedInterestMinor: Int64 = 0,
        cashInvestedMinor: Int64 = 0,
        accountID: UUID? = nil,
        reinvestmentRateBasisPoints: Int? = nil,
        note: String = "",
        status: InvestmentStatus = .active,
        annualRateBasisPoints: Decimal = 0,
        compounding: InvestmentCompounding = .daily,
        startDate: Date? = nil,
        marketValueMinor: Int64? = nil,
        couponDateOverrides: [Date] = []
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
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
        self.statusRaw = status.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.annualRateBasisPoints = annualRateBasisPoints
        self.compoundingRaw = compounding.rawValue
        self.startDate = startDate
        self.marketValueMinor = marketValueMinor
        self.couponDateOverrides = couponDateOverrides
    }

    public var type: InvestmentType {
        get { InvestmentType(rawValue: typeRaw) ?? .treasuryBond }
        set { typeRaw = newValue.rawValue }
    }

    public var status: InvestmentStatus {
        get { InvestmentStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    public var compounding: InvestmentCompounding {
        get { InvestmentCompounding(rawValue: compoundingRaw) ?? .daily }
        set { compoundingRaw = newValue.rawValue }
    }

    public var currency: Currency {
        CurrencyCatalog.currency(for: currencyCode)
    }

    public var nominal: Money {
        Money(minorUnits: nominalMinor, currency: currency)
    }

    public var cashInvested: Money {
        Money(minorUnits: cashInvestedMinor, currency: currency)
    }

    public var isActive: Bool {
        !isSoftDeleted && status == .active
    }

    public var isPending: Bool {
        !isSoftDeleted && status == .pending
    }

    public var isMatured: Bool {
        !isSoftDeleted && status == .matured
    }

    /// The rate used for projections: the per-investment override, or the portfolio default.
    public var effectiveReinvestmentRateBasisPoints: Int {
        reinvestmentRateBasisPoints ?? AppSettings.defaultReinvestmentRateBasisPoints
    }

    public var effectiveWithholdingTaxBasisPoints: Int {
        taxExempt ? 0 : withholdingTaxBasisPoints
    }

    /// Cost basis until a manual market value exists; daily-compounded value for money
    /// Face value still to be redeemed. Partial redemptions reduce this figure.
    public var remainingFaceMinor: Int64 {
        let redeemed =
            (cashFlows ?? [])
            .filter { $0.kind == .redemption && !$0.isSoftDeleted }
            .reduce(Int64(0)) { $0 + $1.netMinor }
        return max(0, nominalMinor - redeemed)
    }

    /// market accounts; zero once matured.
    public func currentValueMinor(asOf date: Date = Date()) -> Int64 {
        InvestmentMath.currentValueMinor(for: self, asOf: date)
    }

    public var currentValue: Money {
        Money(minorUnits: currentValueMinor(), currency: currency)
    }
}
