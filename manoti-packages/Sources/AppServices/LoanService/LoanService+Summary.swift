//
//  LoanService+Summary.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

nonisolated public struct LoanSummary: Equatable, Sendable {
    public let receivable: Money
    public let payable: Money
    public let missingRates: [String]

    public init(receivable: Money, payable: Money, missingRates: [String]) {
        self.receivable = receivable
        self.payable = payable
        self.missingRates = missingRates
    }
}

extension LoanService {
    /// Open receivables and payables in the display currency.
    ///
    /// A missing rate is marked and converted 1:1 in major units, exactly like account
    /// balances.
    public func summary(displayCurrency: Currency) throws -> LoanSummary {
        let book = try rateBook()
        var receivable: Int64 = 0
        var payable: Int64 = 0
        var missing: Set<String> = []

        for loan in try fetchLoans(includeSettled: false) {
            let outstanding = loan.outstanding
            guard !outstanding.isZero else {
                continue
            }

            let converted: Money
            if let value = book.convert(outstanding, to: displayCurrency, on: Date()) {
                converted = value
            } else {
                missing.insert(loan.currency.code)
                converted = fallback(outstanding, to: displayCurrency)
            }

            switch loan.direction {
                case .lent:
                    receivable += converted.minorUnits
                case .borrowed:
                    payable += converted.minorUnits
            }
        }

        return LoanSummary(
            receivable: Money(minorUnits: receivable, currency: displayCurrency),
            payable: Money(minorUnits: payable, currency: displayCurrency),
            missingRates: missing.sorted()
        )
    }

    private func rateBook() throws -> ExchangeRateBook {
        let records = try context.fetch(
            FetchDescriptor<ExchangeRateRecord>(sortBy: [SortDescriptor(\ExchangeRateRecord.asOf, order: .reverse)])
        )
        return ExchangeRateBook(records: records)
    }

    /// Reinterprets the major-unit amount in the display currency.
    ///
    /// Used only when no rate is available, so the caller can show the amount 1:1 without
    /// rescaling by exponent.
    private func fallback(_ money: Money, to currency: Currency) -> Money {
        Money(decimal: money.decimalValue, currency: currency) ?? .zero(in: currency)
    }
}
