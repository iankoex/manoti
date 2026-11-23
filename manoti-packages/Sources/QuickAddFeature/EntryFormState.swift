//
//  EntryFormState.swift
//  QuickAddFeature
//

import AppModels
import AppServices
import Foundation
import Observation

@MainActor
@Observable
public final class EntryFormState {
    public enum AmountField: Hashable {
        case amount
        case fee
    }

    public var kind: LedgerEntryKind = .expense
    public var amountText = ""
    public var feeText = ""
    public var activeField: AmountField = .amount
    public var note = ""
    public var occurredAt = Date.now
    public var selectedAccountID: UUID?
    public var selectedCategoryID: UUID?
    public var showsDetails = false

    public var accounts: [Account] = []
    public var groups: [CategoryGroup] = []
    public var categories: [SpendingCategory] = []

    public init() {}

    /// Groups that contain at least one category for the current entry kind.
    public var visibleGroups: [CategoryGroup] {
        let kind = self.kind.categoryKind
        return groups.compactMap { group in
            let matching = group.visibleCategories.filter { $0.kind == kind }
            guard !matching.isEmpty else {
                return nil
            }

            return group
        }
    }

    /// Non-archived categories of the current kind, in group order.
    public var availableCategories: [SpendingCategory] {
        let kind = self.kind.categoryKind
        return categories.filter { $0.kind == kind }
    }

    public var selectedCategory: SpendingCategory? {
        guard let selectedCategoryID else {
            return nil
        }

        return availableCategories.first { $0.id == selectedCategoryID }
    }

    /// Changes the entry kind and clears a category that no longer applies.
    public func setKind(_ kind: LedgerEntryKind) {
        let current = categories.first { $0.id == selectedCategoryID }
        self.kind = kind

        if let current, current.kind != kind.categoryKind {
            selectedCategoryID = nil
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

    public var feeMinor: Int64? {
        guard let account = selectedAccount, !feeText.isEmpty else {
            return nil
        }

        return MoneyParser.parse(feeText, defaultCurrency: account.currency)?.money.minorUnits
    }

    public var canSave: Bool {
        guard let account = selectedAccount else {
            return false
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: account.currency) else {
            return false
        }

        return parsed.money.minorUnits > 0
    }

    public func reload(accountService: AccountService, categoryService: CategoryService) {
        accounts = (try? accountService.fetchAccounts()) ?? []
        groups = (try? categoryService.fetchGroups()) ?? []
        categories = groups.flatMap(\.visibleCategories)
    }

    public func selectDefaultAccount(lastAccountID: String) {
        if let selectedAccountID, activeAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        if let stored = UUID(uuidString: lastAccountID),
            activeAccounts.contains(where: { $0.id == stored })
        {
            selectedAccountID = stored
        } else {
            selectedAccountID = activeAccounts.first?.id
        }
    }

    public func press(_ key: String) {
        switch activeField {
            case .amount:
                AmountEntry.apply(key, to: &amountText)
            case .fee:
                AmountEntry.apply(key, to: &feeText)
        }
    }

    @discardableResult
    public func save(ledger: LedgerService) throws -> LedgerEntry {
        guard let account = selectedAccount else {
            throw EntryFormError.missingAccount
        }

        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: account.currency),
            parsed.money.minorUnits > 0
        else {
            throw EntryFormError.invalidAmount
        }

        let category = availableCategories.first { $0.id == selectedCategoryID }

        return try ledger.record(
            kind: kind,
            amountMinor: parsed.money.minorUnits,
            feeMinor: feeMinor ?? 0,
            account: account,
            category: category,
            payee: "",
            note: note,
            occurredAt: occurredAt
        )
    }
}

public enum EntryFormError: Error, Equatable {
    case missingAccount
    case invalidAmount
}
