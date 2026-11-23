//
//  InvestmentFormState.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Foundation
import Observation

public enum InvestmentFormError: Error, Equatable {
    case invalidInput
}

/// Editable state for creating a bond, Treasury bill or money market account.
///
/// Validation mirrors `InvestmentService` so Save stays disabled until the service would
/// accept the input. Amounts use `MoneyParser`; rates are percentages in the UI.
@MainActor
@Observable
public final class InvestmentFormState {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case bond
        case bill
        case moneyMarket

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
                case .bond: "Treasury bond"
                case .bill: "Treasury bill"
                case .moneyMarket: "Money market"
            }
        }

        public var investmentType: InvestmentType {
            switch self {
                case .bond: .treasuryBond
                case .bill: .treasuryBill
                case .moneyMarket: .moneyMarket
            }
        }
    }

    public var mode: Mode

    // Shared
    public var issueNumber = ""
    public var isin = ""
    public var note = ""
    public var selectedAccountID: UUID?
    public var accounts: [Account] = []
    public var withholdingTaxText = "10.00"
    public var taxExempt = false

    // Bonds and bills
    public var nominalText = ""
    public var purchaseDate = Date.now

    // Bonds
    public var couponRateText = "12.00"
    public var issueDate: Date?
    public var settlementDate: Date?
    public var firstCouponDate: Date?
    public var maturityDate: Date?
    public var cleanPriceText = "100.00"
    public var accruedInterestText = ""
    public var cashInvestedText = ""
    public var reinvestmentRateText = ""

    // Bills
    public var purchasePriceText = ""

    // Money market
    public var principalText = ""
    public var annualRateText = ""
    public var startDate = Date.now

    public init(mode: Mode = .bond) {
        self.mode = mode

        let calendar = InvestmentMath.calendar
        switch mode {
            case .bond:
                firstCouponDate = calendar.date(byAdding: .month, value: 6, to: purchaseDate)
                maturityDate = calendar.date(byAdding: .year, value: 10, to: purchaseDate)

            case .bill:
                firstCouponDate = nil
                maturityDate = calendar.date(byAdding: .day, value: 364, to: purchaseDate)

            case .moneyMarket:
                firstCouponDate = nil
                maturityDate = nil
        }
    }

    public var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    public var selectedAccount: Account? {
        guard let selectedAccountID else {
            return activeAccounts.first
        }

        return activeAccounts.first { $0.id == selectedAccountID }
    }

    public var currency: Currency {
        selectedAccount?.currency ?? CurrencyCatalog.defaultCurrency
    }

    public var parsedNominal: Money? {
        MoneyParser.parse(nominalText, defaultCurrency: currency)?.money
    }

    public var parsedPrincipal: Money? {
        MoneyParser.parse(principalText, defaultCurrency: currency)?.money
    }

    public var parsedPurchasePrice: Money? {
        MoneyParser.parse(purchasePriceText, defaultCurrency: currency)?.money
    }

    public var couponRateBasisPoints: Decimal? {
        rateBasisPoints(from: couponRateText)
    }

    public var annualRateBasisPoints: Decimal? {
        rateBasisPoints(from: annualRateText)
    }

    public var withholdingTaxBasisPoints: Int? {
        guard let value = decimal(withholdingTaxText) else {
            return nil
        }

        return roundedBasisPoints(value * 100)
    }

    public var cleanPricePer100: Decimal? {
        decimal(cleanPriceText)
    }

    public var accruedInterestMinor: Int64? {
        guard let nominal = parsedNominal?.minorUnits else {
            return nil
        }

        if accruedInterestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 0
        }

        guard let accrued = MoneyParser.parse(accruedInterestText, defaultCurrency: currency)?.money
        else {
            return nil
        }

        guard accrued.minorUnits >= 0, accrued.minorUnits <= nominal else {
            return nil
        }

        return accrued.minorUnits
    }

    /// Clean price plus accrued interest, the cash a reopened bond costs.
    public var dirtyPrice: Money? {
        guard let nominal = parsedNominal?.minorUnits else {
            return nil
        }

        let cleanMinor: Int64
        if let cleanPricePer100 {
            guard cleanPricePer100 > 0 else {
                return nil
            }
            cleanMinor = InvestmentMath.cleanPriceMinor(
                nominalMinor: nominal,
                pricePer100: cleanPricePer100
            )
        } else {
            cleanMinor = nominal
        }

        guard let accrued = accruedInterestMinor else {
            return nil
        }

        return Money(minorUnits: cleanMinor + accrued, currency: currency)
    }

    public var reinvestmentRateOverrideBasisPoints: Int? {
        guard !reinvestmentRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let percent = decimal(reinvestmentRateText) else {
            return nil
        }

        return roundedBasisPoints(percent * 100)
    }

    public var validationMessages: [String] {
        var messages = nonNegativeRateMessages

        if let account = selectedAccount, account.currencyCode != CurrencyCatalog.defaultCurrency.code {
            messages.append("Investments are recorded in KES. Choose a KES account.")
        }

        switch mode {
            case .bond: messages.append(contentsOf: bondMessages)
            case .bill: messages.append(contentsOf: billMessages)
            case .moneyMarket: messages.append(contentsOf: moneyMarketMessages)
        }

        return messages
    }

    public var canSave: Bool {
        validationMessages.isEmpty
    }

    public func reload(accountService: AccountService) {
        accounts = (try? accountService.fetchAccounts(includeArchived: true)) ?? []
        selectDefaultAccount()
    }

    public func selectDefaultAccount() {
        if let selectedAccountID, activeAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        selectedAccountID = activeAccounts.first?.id
    }

    @discardableResult
    public func save(investmentService: InvestmentService) throws -> Investment {
        guard canSave else {
            throw InvestmentFormError.invalidInput
        }

        let account = selectedAccount
        let tax = withholdingTaxBasisPoints ?? InvestmentScenario.defaultWithholdingTaxBasisPoints

        switch mode {
            case .bond:
                guard let nominal = parsedNominal,
                    let couponRate = couponRateBasisPoints,
                    let maturityDate
                else {
                    throw InvestmentFormError.invalidInput
                }

                let cashInvested = MoneyParser.parse(cashInvestedText, defaultCurrency: currency)?.money

                return try investmentService.createBond(
                    issueNumber: issueNumber,
                    isin: isin,
                    nominalMinor: nominal.minorUnits,
                    couponRateBasisPoints: couponRate,
                    firstCouponDate: firstCouponDate,
                    maturityDate: maturityDate,
                    purchaseDate: purchaseDate,
                    settlementDate: settlementDate,
                    issueDate: issueDate,
                    withholdingTaxBasisPoints: tax,
                    taxExempt: taxExempt,
                    cleanPrice: cleanPricePer100,
                    accruedInterestMinor: accruedInterestMinor ?? 0,
                    cashInvestedMinor: cashInvested?.minorUnits,
                    account: account,
                    reinvestmentRateBasisPoints: reinvestmentRateOverrideBasisPoints,
                    note: note
                )

            case .bill:
                guard let nominal = parsedNominal,
                    let price = parsedPurchasePrice,
                    let maturityDate
                else {
                    throw InvestmentFormError.invalidInput
                }

                return try investmentService.createTreasuryBill(
                    nominalMinor: nominal.minorUnits,
                    purchasePriceMinor: price.minorUnits,
                    purchaseDate: purchaseDate,
                    maturityDate: maturityDate,
                    withholdingTaxBasisPoints: tax,
                    taxExempt: taxExempt,
                    account: account,
                    note: note
                )

            case .moneyMarket:
                guard let principal = parsedPrincipal, let annualRate = annualRateBasisPoints else {
                    throw InvestmentFormError.invalidInput
                }

                return try investmentService.createMoneyMarket(
                    principalMinor: principal.minorUnits,
                    annualRateBasisPoints: annualRate,
                    startDate: startDate,
                    withholdingTaxBasisPoints: tax,
                    taxExempt: taxExempt,
                    account: account,
                    note: note
                )
        }
    }

    // MARK: - Validation

    private var nonNegativeRateMessages: [String] {
        var messages: [String] = []

        if withholdingTaxBasisPoints == nil {
            messages.append("Enter a withholding tax between 0% and 100%.")
        } else if let tax = withholdingTaxBasisPoints, tax > 10_000 {
            messages.append("Enter a withholding tax between 0% and 100%.")
        }

        if !reinvestmentRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let override = reinvestmentRateOverrideBasisPoints {
                if override < 0 || override > 5000 {
                    messages.append("Enter a reinvestment rate between 0% and 50%.")
                }
            } else {
                messages.append("Enter a valid reinvestment rate.")
            }
        }

        return messages
    }

    private var bondMessages: [String] {
        var messages: [String] = []

        if (parsedNominal?.minorUnits ?? 0) <= 0 {
            messages.append("Enter a nominal amount greater than zero.")
        }

        if let couponRateBasisPoints {
            if couponRateBasisPoints < 0 || couponRateBasisPoints > 10_000 {
                messages.append("Enter a coupon rate between 0% and 100%.")
            }
        } else {
            messages.append("Enter the annual coupon rate.")
        }

        guard let maturityDate else {
            messages.append("Choose a maturity date.")
            return messages
        }

        if purchaseDate > maturityDate {
            messages.append("Maturity must be after the purchase date.")
        }

        if let firstCouponDate, firstCouponDate > maturityDate {
            messages.append("The first coupon must be on or before maturity.")
        }

        if let firstCouponDate, firstCouponDate < purchaseDate {
            messages.append("The first coupon cannot be before the purchase date.")
        }

        if let issueDate, issueDate > purchaseDate {
            messages.append("The issue date cannot be after the purchase date.")
        }

        if let settlementDate, settlementDate < purchaseDate {
            messages.append("Settlement cannot be before the purchase date.")
        }

        if !cleanPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let cleanPricePer100 {
                if cleanPricePer100 <= 0 || cleanPricePer100 > 200 {
                    messages.append("Enter a clean price between 0 and 200 per 100 nominal.")
                }
            } else {
                messages.append("Enter a valid clean price.")
            }
        }

        if !accruedInterestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            accruedInterestMinor == nil
        {
            messages.append("Enter accrued interest between zero and the nominal.")
        }

        if !cashInvestedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let cash = MoneyParser.parse(cashInvestedText, defaultCurrency: currency)?.money {
                if cash.minorUnits <= 0 {
                    messages.append("Cash invested must be greater than zero.")
                }
            } else {
                messages.append("Enter a valid cash invested amount.")
            }
        }

        return messages
    }

    private var billMessages: [String] {
        var messages: [String] = []

        let nominal = parsedNominal?.minorUnits ?? 0
        if nominal <= 0 {
            messages.append("Enter a nominal amount greater than zero.")
        }

        if let price = parsedPurchasePrice?.minorUnits {
            if price <= 0 {
                messages.append("Enter the price paid, greater than zero.")
            } else if nominal > 0, price > nominal {
                messages.append("A Treasury bill costs less than its nominal.")
            }
        } else {
            messages.append("Enter the price paid for the bill.")
        }

        guard let maturityDate else {
            messages.append("Choose a maturity date.")
            return messages
        }

        if purchaseDate >= maturityDate {
            messages.append("Maturity must be after the purchase date.")
        }

        return messages
    }

    private var moneyMarketMessages: [String] {
        var messages: [String] = []

        if (parsedPrincipal?.minorUnits ?? 0) <= 0 {
            messages.append("Enter a principal greater than zero.")
        }

        if let annualRateBasisPoints {
            if annualRateBasisPoints < 0 || annualRateBasisPoints > 10_000 {
                messages.append("Enter an annual rate between 0% and 100%.")
            }
        } else {
            messages.append("Enter the annual interest rate.")
        }

        return messages
    }

    // MARK: - Parsing

    private func rateBasisPoints(from text: String) -> Decimal? {
        guard let percent = decimal(text) else {
            return nil
        }

        return percent * 100
    }

    private func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var normalised = trimmed.replacingOccurrences(of: " ", with: "")

        if normalised.contains(",") {
            if normalised.contains(".") {
                // `1,234.56`: the dot is the decimal separator.
                normalised = normalised.replacingOccurrences(of: ",", with: "")
            } else {
                let trailing = normalised.split(separator: ",").last?.count ?? 0
                normalised =
                    trailing <= 2
                    ? normalised.replacingOccurrences(of: ",", with: ".")
                    : normalised.replacingOccurrences(of: ",", with: "")
            }
        }

        guard let value = Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        guard value >= 0 else {
            return nil
        }

        return value
    }

    private func roundedBasisPoints(_ value: Decimal) -> Int {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).intValue
    }
}
