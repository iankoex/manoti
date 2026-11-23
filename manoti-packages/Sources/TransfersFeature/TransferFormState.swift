//
//  TransferFormState.swift
//  TransfersFeature
//

import AppModels
import AppServices
import Foundation
import Observation

@MainActor
@Observable
public final class TransferFormState {
    public enum AmountField: Hashable {
        case amount
        case fee
        case received
    }

    public var fromID: UUID? {
        didSet {
            if oldValue != fromID {
                receivedText = ""
            }
        }
    }
    public var toID: UUID? {
        didSet {
            if oldValue != toID {
                receivedText = ""
            }
        }
    }
    public var amountText = ""
    public var receivedText = ""
    public var feeText = ""
    public var activeField: AmountField = .amount
    public var note = ""
    public var occurredAt = Date.now
    public var showsDetails = false

    public var accounts: [Account] = []

    public init(initialFrom: UUID? = nil) {
        self.fromID = initialFrom
    }

    public var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    public var fromAccount: Account? {
        activeAccounts.first { $0.id == fromID }
    }

    public var toAccount: Account? {
        activeAccounts.first { $0.id == toID }
    }

    public var availableTargets: [Account] {
        activeAccounts.filter { $0.id != fromID }
    }

    public var requiresConvertedAmount: Bool {
        guard let fromAccount, let toAccount else {
            return false
        }

        return fromAccount.currency != toAccount.currency
    }

    public var canSave: Bool {
        guard let fromAccount, let toAccount, fromAccount.id != toAccount.id else {
            return false
        }

        guard let sent = MoneyParser.parse(amountText, defaultCurrency: fromAccount.currency),
            sent.money.minorUnits > 0
        else {
            return false
        }

        if requiresConvertedAmount {
            guard let received = MoneyParser.parse(receivedText, defaultCurrency: toAccount.currency),
                received.money.minorUnits > 0
            else {
                return false
            }
        }

        let trimmedFee = feeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFee.isEmpty {
            guard let fee = MoneyParser.parse(trimmedFee, defaultCurrency: fromAccount.currency),
                fee.money.minorUnits >= 0
            else {
                return false
            }
        }

        return true
    }

    public var balancePreview: [(name: String, balance: Money)]? {
        guard let fromAccount, let toAccount,
            let sent = MoneyParser.parse(amountText, defaultCurrency: fromAccount.currency)
        else {
            return nil
        }

        let fee = MoneyParser.parse(feeText, defaultCurrency: fromAccount.currency)?.money.minorUnits ?? 0
        let received =
            requiresConvertedAmount
            ? MoneyParser.parse(receivedText, defaultCurrency: toAccount.currency)?.money.minorUnits ?? 0
            : sent.money.minorUnits

        return [
            (
                fromAccount.displayName,
                Money(
                    minorUnits: fromAccount.balance.minorUnits - sent.money.minorUnits - fee,
                    currency: fromAccount.currency
                )
            ),
            (
                toAccount.displayName,
                Money(minorUnits: toAccount.balance.minorUnits + received, currency: toAccount.currency)
            ),
        ]
    }

    public func reload(accountService: AccountService) {
        accounts = (try? accountService.fetchAccounts()) ?? []
    }

    public func selectDefaults() {
        if fromAccount == nil {
            fromID = activeAccounts.first?.id
        }

        if toAccount == nil || toAccount?.id == fromID {
            toID = availableTargets.first?.id
        }
    }

    public func press(_ key: String) {
        switch activeField {
            case .amount:
                AmountEntry.apply(key, to: &amountText)
            case .fee:
                AmountEntry.apply(key, to: &feeText)
            case .received:
                guard requiresConvertedAmount else {
                    return
                }

                AmountEntry.apply(key, to: &receivedText)
        }
    }

    public func save(transferService: TransferService) throws {
        guard let fromAccount, let toAccount else {
            throw TransferError.sameAccount
        }

        let sent = MoneyParser.parse(amountText, defaultCurrency: fromAccount.currency)?.money.minorUnits ?? 0
        let received =
            requiresConvertedAmount
            ? MoneyParser.parse(receivedText, defaultCurrency: toAccount.currency)?.money.minorUnits
            : sent

        let trimmedFee = feeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fee: Int64
        if trimmedFee.isEmpty {
            fee = 0
        } else {
            guard let parsed = MoneyParser.parse(trimmedFee, defaultCurrency: fromAccount.currency),
                parsed.money.minorUnits >= 0
            else {
                throw TransferError.invalidAmount
            }
            fee = parsed.money.minorUnits
        }

        try transferService.transfer(
            from: fromAccount,
            to: toAccount,
            amountOutMinor: sent,
            amountInMinor: received,
            feeMinor: fee,
            occurredAt: occurredAt,
            note: note
        )
    }
}
