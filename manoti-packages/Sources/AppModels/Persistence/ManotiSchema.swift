//
//  ManotiSchema.swift
//  AppModels
//

import Foundation
import SwiftData

public enum ManotiSchema {
    public static let models: [any PersistentModel.Type] = [
        Account.self,
        AccountIdentifier.self,
        LedgerEntry.self,
        Transfer.self,
        CategoryGroup.self,
        SpendingCategory.self,
        ExchangeRateRecord.self,
        AppSettings.self,
        ParseRuleSet.self,
        ParseRule.self,
        MerchantMemory.self,
        MerchantAlias.self,
        IngestMemory.self,
        SmartRule.self,
        ContextWindow.self,
        Loan.self,
        Investment.self,
        InvestmentCashFlow.self,
        BudgetPeriod.self,
        Envelope.self,
        SinkingFund.self,
        SinkingFundContribution.self,
        Goal.self,
        BudgetAlert.self,
        ReconcileSession.self,
        ReconcileMessage.self,
        UnparsedMessage.self,
    ]
}
