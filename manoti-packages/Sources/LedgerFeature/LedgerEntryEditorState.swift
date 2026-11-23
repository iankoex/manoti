//
//  LedgerEntryEditorState.swift
//  LedgerFeature
//

import AppModels
import AppServices
import Foundation
import Observation

/// Editable state for one ledger entry.
///
/// Ordinary expenses and incomes may change their kind. Adjustments and opening balances
/// keep the kind they were recorded with, because its sign carries meaning. Entry rows that
/// belong to a transfer, loan or investment are surfaced as read-only here; they are edited
/// from their own screens.
@MainActor
@Observable
public final class LedgerEntryEditorState {
    public enum ValidationError: Error, Equatable {
        case linkedEntry
        case unsupportedKind
        case missingAccount
        case archivedAccount
        case invalidAmount
    }

    public let entry: LedgerEntry
    public private(set) var accounts: [Account]
    public private(set) var categories: [SpendingCategory]

    public var kind: LedgerEntryKind
    public var amountText: String
    public var feeText: String
    public var occurredAt: Date
    public var accountID: UUID?
    public var categoryID: UUID?
    public var payee: String
    public var note: String

    public init(entry: LedgerEntry, accounts: [Account], categories: [SpendingCategory]) {
        let activeAccounts =
            accounts
            .filter {
                !$0.isArchived
                    && (entry.currencyCode.isEmpty || $0.currencyCode == entry.currencyCode)
            }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        var sortedCategories = categories
        // Keep the entry's own category selectable even when its group has been archived,
        // so opening the editor never silently clears it.
        if let category = entry.category, !sortedCategories.contains(where: { $0.id == category.id }) {
            sortedCategories.append(category)
        }
        sortedCategories.sort { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        self.entry = entry
        self.accounts = activeAccounts
        self.categories = sortedCategories

        kind = entry.kind
        amountText = Self.plainText(minorUnits: entry.amountMinor, currency: entry.currency)
        feeText = entry.feeMinor == 0 ? "" : Self.plainText(minorUnits: entry.feeMinor, currency: entry.currency)
        occurredAt = entry.occurredAt
        accountID =
            entry.account.flatMap { account in
                activeAccounts.contains(where: { $0.id == account.id }) ? account.id : nil
            }
        categoryID = entry.category?.id
        payee = entry.payee
        note = entry.note
    }

    /// True while the entry is owned by another feature and must not be edited here.
    public var isLinkedEntry: Bool {
        entry.transfer != nil || entry.loan != nil || entry.investmentCashFlow != nil
    }

    /// Expenses and incomes may switch direction; every other supported kind is fixed.
    public var isKindEditable: Bool {
        !isLinkedEntry && (entry.kind == .expense || entry.kind == .income)
    }

    /// The kinds the picker offers. A fixed kind is returned alone so the selection stays valid.
    public var kindOptions: [LedgerEntryKind] {
        isKindEditable ? [.expense, .income] : [kind]
    }

    public var selectedAccount: Account? {
        guard let accountID else {
            return nil
        }

        return accounts.first { $0.id == accountID }
    }

    public var selectedCategory: SpendingCategory? {
        guard let categoryID else {
            return nil
        }

        return categories.first { $0.id == categoryID }
    }

    /// Categories that match the entry's kind, plus the one already attached.
    public var visibleCategories: [SpendingCategory] {
        categories.filter { $0.kind == kind.categoryKind || $0.id == entry.category?.id }
    }

    /// The currency amounts are parsed and displayed in.
    public var currency: Currency {
        selectedAccount?.currency ?? entry.currency
    }

    /// The parsed amount, keeping the sign typed for adjustments and opening balances.
    public var parsedAmount: Money? {
        MoneyParser.parse(amountText, defaultCurrency: currency)?.money
    }

    /// The parsed fee, or zero when the field is empty.
    public var parsedFeeMinor: Int64? {
        guard !trimmed(feeText).isEmpty else {
            return 0
        }

        return MoneyParser.parse(feeText, defaultCurrency: currency)?.money.minorUnits
    }

    /// Flips the sign for adjustments and opening balances, the only kinds whose sign is
    /// meaningful. The decimal keyboard has no minus key.
    public func toggleAmountSign() {
        guard kind == .adjustment || kind == .openingBalance else {
            return
        }

        if amountText.hasPrefix("-") {
            amountText.removeFirst()
        } else if amountText.hasPrefix("\u{2212}") {
            amountText.removeFirst()
        } else if !amountText.isEmpty {
            amountText = "-" + amountText
        }
    }

    public var trimmedPayee: String {
        trimmed(payee)
    }

    public var trimmedNote: String {
        trimmed(note)
    }

    public var validationMessage: String? {
        if isLinkedEntry {
            return "This entry belongs to a transfer, loan or investment. Change it from its own screen."
        }

        guard isSupportedKind else {
            return "This entry can't be edited here."
        }

        guard selectedAccount != nil else {
            return accounts.isEmpty ? "No active accounts available." : "Choose an account."
        }

        if let selectedCategory, selectedCategory.kind != kind.categoryKind {
            return "Choose a category that matches this entry kind."
        }

        guard let amount = parsedAmount else {
            return "Enter a valid amount."
        }

        if kind == .adjustment || kind == .openingBalance {
            guard amount.minorUnits != 0 else {
                return "Enter a non-zero amount."
            }
        } else {
            guard amount.minorUnits > 0 else {
                return "Enter an amount greater than zero."
            }
        }

        guard let feeMinor = parsedFeeMinor else {
            return "Enter a valid fee."
        }

        guard feeMinor >= 0 else {
            return "Enter a fee of zero or more."
        }

        return nil
    }

    public var canSave: Bool {
        validationMessage == nil
    }

    @discardableResult
    public func save(using ledgerService: LedgerService) throws -> LedgerEntry {
        guard !isLinkedEntry else {
            throw ValidationError.linkedEntry
        }

        guard isSupportedKind else {
            throw ValidationError.unsupportedKind
        }

        guard let account = selectedAccount else {
            throw ValidationError.missingAccount
        }

        guard !account.isArchived else {
            throw ValidationError.archivedAccount
        }

        guard let amount = parsedAmount else {
            throw ValidationError.invalidAmount
        }

        if kind == .adjustment || kind == .openingBalance {
            guard amount.minorUnits != 0 else {
                throw ValidationError.invalidAmount
            }
        } else {
            guard amount.minorUnits > 0 else {
                throw ValidationError.invalidAmount
            }
        }

        guard let feeMinor = parsedFeeMinor, feeMinor >= 0 else {
            throw ValidationError.invalidAmount
        }

        return try ledgerService.update(
            entry,
            kind: kind,
            amountMinor: amount.minorUnits,
            feeMinor: feeMinor,
            account: account,
            category: selectedCategory,
            payee: trimmedPayee,
            note: trimmedNote,
            occurredAt: occurredAt
        )
    }

    /// Plain editable text for a minor-unit amount, with no grouping or currency token.
    static func plainText(minorUnits: Int64, currency: Currency) -> String {
        let money = Money(minorUnits: minorUnits, currency: currency)
        return NSDecimalNumber(decimal: money.decimalValue).stringValue
    }

    private var isSupportedKind: Bool {
        switch kind {
            case .expense, .income, .adjustment, .openingBalance: return true
            default: return false
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
