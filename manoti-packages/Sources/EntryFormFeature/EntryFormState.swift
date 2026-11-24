//
//  EntryFormState.swift
//  EntryFormFeature
//

import AppModels
import AppServices
import Foundation
import Observation

/// Editable state for one entry, shared by Add, Inbox review and Ledger edit.
///
/// Create mode records a new entry. Edit and review modes pre-fill from an existing
/// `LedgerEntry` and update it in place, keeping its identity, source, raw message,
/// references and status.
@MainActor
@Observable
public final class EntryFormState {
    public enum Purpose: Sendable {
        case create
        case edit
        case review
    }

    public enum AmountField: Hashable {
        case amount
        case fee
    }

    public let purpose: Purpose
    public let entry: LedgerEntry?

    public var kind: LedgerEntryKind
    public var amountText = ""
    public var feeText = ""
    public var activeField: AmountField = .amount
    public var note = ""
    public var payee = ""
    public var occurredAt: Date
    public var selectedAccountID: UUID?
    public var selectedCategoryID: UUID?

    public var accounts: [Account] = []
    public var groups: [CategoryGroup] = []
    public var categories: [SpendingCategory] = []

    /// Kept for the review screen's caption. Informational only.
    public var suggestionNote: String?

    private let pinnedCategory: SpendingCategory?
    private var isAmountPristine: Bool
    private var isFeePristine: Bool

    public init(
        purpose: Purpose = .create,
        entry: LedgerEntry? = nil,
        accounts: [Account] = [],
        groups: [CategoryGroup] = [],
        categories: [SpendingCategory] = []
    ) {
        self.purpose = purpose
        self.entry = entry
        self.kind = entry?.kind ?? .expense
        self.occurredAt = entry?.occurredAt ?? .now
        self.payee = entry?.payee ?? ""
        self.note = entry?.note ?? ""
        self.selectedAccountID = entry?.account?.id
        self.selectedCategoryID = entry?.category?.id
        self.pinnedCategory = entry?.category
        self.isAmountPristine = entry != nil
        self.isFeePristine = entry.map { $0.feeMinor != 0 } ?? false

        if let entry {
            amountText = Self.plainText(minorUnits: entry.amountMinor, currency: entry.currency)
            feeText = entry.feeMinor == 0 ? "" : Self.plainText(minorUnits: entry.feeMinor, currency: entry.currency)
        }

        if !accounts.isEmpty || !groups.isEmpty || !categories.isEmpty {
            setOptions(accounts: accounts, groups: groups, categories: categories)
        }
    }

    // MARK: - Options

    public func setOptions(
        accounts: [Account],
        groups: [CategoryGroup],
        categories: [SpendingCategory]
    ) {
        let allowedCurrency = entry?.currencyCode

        self.accounts =
            accounts
            .filter { account in
                guard !account.isArchived else {
                    return false
                }

                guard let allowedCurrency, !allowedCurrency.isEmpty else {
                    return true
                }

                return account.currencyCode == allowedCurrency
            }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        self.groups = groups

        var all = categories
        // Keep an archived or otherwise unlisted current category selectable, so a save
        // with no interaction never silently clears categorisation.
        if let pinnedCategory, !all.contains(where: { $0.id == pinnedCategory.id }) {
            all.append(pinnedCategory)
        }
        self.categories = all

        if let selectedAccountID, !self.accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = nil
        }

        // A message that was never routed starts with the first matching account, the
        // same convenience the old review screen offered. An entry whose account was
        // archived stays unselected so the user has to choose deliberately.
        if purpose == .review, selectedAccountID == nil, entry?.account == nil {
            selectedAccountID = self.accounts.first?.id
        }
    }

    public func reload(accountService: AccountService, categoryService: CategoryService) {
        let accounts = (try? accountService.fetchAccounts()) ?? []
        let groups = (try? categoryService.fetchGroups()) ?? []
        setOptions(
            accounts: accounts,
            groups: groups,
            categories: groups.flatMap(\.visibleCategories)
        )
    }

    public func selectDefaultAccount(lastAccountID: String) {
        if let selectedAccountID, accounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        if let stored = UUID(uuidString: lastAccountID),
            accounts.contains(where: { $0.id == stored })
        {
            selectedAccountID = stored
        } else {
            selectedAccountID = accounts.first?.id
        }
    }

    // MARK: - Derived

    /// True while the entry is owned by another feature and must not be edited here.
    public var isLinkedEntry: Bool {
        entry?.transfer != nil || entry?.loan != nil || entry?.investmentCashFlow != nil
    }

    /// Expenses and incomes may switch direction; every other kind keeps its meaning.
    public var isKindEditable: Bool {
        !isLinkedEntry && kindOptions.count > 1
    }

    public var kindOptions: [LedgerEntryKind] {
        if isLinkedEntry {
            return [kind]
        }

        switch purpose {
            case .create:
                return [.expense, .income]
            case .edit, .review:
                if kind == .expense || kind == .income {
                    return [.expense, .income]
                }

                return [kind]
        }
    }

    /// Category has no effect on a transfer leg, so the control is hidden there.
    public var showsCategory: Bool {
        !isLinkedEntry && !kind.isTransferLeg
    }

    public var isSupportedKind: Bool {
        if purpose == .create {
            return kind == .expense || kind == .income
        }

        switch kind {
            case .expense, .income, .adjustment, .openingBalance, .transferOut, .transferIn:
                return true
            default:
                return false
        }
    }

    public var supportsSignToggle: Bool {
        kind == .adjustment || kind == .openingBalance
    }

    public var visibleGroups: [CategoryGroup] {
        let categoryKind = kind.categoryKind
        return groups.compactMap { group in
            let matching = group.visibleCategories.filter { $0.kind == categoryKind }
            guard !matching.isEmpty else {
                return nil
            }

            return group
        }
    }

    /// Non-archived categories of the current kind, in group order.
    public var availableCategories: [SpendingCategory] {
        let categoryKind = kind.categoryKind
        return categories.filter { $0.kind == categoryKind }
    }

    /// The current category when the drill-down cannot list it, so the picker can show it.
    public var pinnedCategoryForPicker: SpendingCategory? {
        guard let pinnedCategory, selectedCategoryID == pinnedCategory.id else {
            return nil
        }

        let listed = groups.contains { group in
            !group.isArchived && group.visibleCategories.contains { $0.id == pinnedCategory.id }
        }

        return listed ? nil : pinnedCategory
    }

    public var selectedAccount: Account? {
        guard let selectedAccountID else {
            return nil
        }

        return accounts.first { $0.id == selectedAccountID }
    }

    public var selectedCategory: SpendingCategory? {
        guard let selectedCategoryID else {
            return nil
        }

        if let match = availableCategories.first(where: { $0.id == selectedCategoryID }) {
            return match
        }

        if let pinnedCategory, pinnedCategory.id == selectedCategoryID {
            return pinnedCategory
        }

        return nil
    }

    public var currency: Currency {
        selectedAccount?.currency ?? entry?.currency ?? CurrencyCatalog.defaultCurrency
    }

    public var parsedAmount: Money? {
        MoneyParser.parse(amountText, defaultCurrency: currency)?.money
    }

    public var feeMinor: Int64? {
        guard !feeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }

        return MoneyParser.parse(feeText, defaultCurrency: currency)?.money.minorUnits
    }

    public var parsedFeeMinor: Int64? {
        feeMinor
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

        if showsCategory, let selectedCategory, selectedCategory.kind != kind.categoryKind {
            return "Choose a category that matches this entry kind."
        }

        guard let amount = parsedAmount else {
            return "Enter a valid amount."
        }

        if supportsSignToggle {
            guard amount.minorUnits != 0 else {
                return "Enter a non-zero amount."
            }
        } else {
            guard amount.minorUnits > 0 else {
                return "Enter an amount greater than zero."
            }
        }

        guard let feeMinor, feeMinor >= 0 else {
            return "Enter a fee of zero or more."
        }

        return nil
    }

    public var canSave: Bool {
        validationMessage == nil
    }

    // MARK: - Editing

    public func setKind(_ kind: LedgerEntryKind) {
        let current = availableCategories.first { $0.id == selectedCategoryID }
        self.kind = kind

        if let current, current.kind != kind.categoryKind {
            selectedCategoryID = nil
        }
    }

    public func applySuggestion(_ suggestion: CategorySuggestion?) {
        guard purpose == .review, entry?.category == nil, let suggestion else {
            return
        }

        selectedCategoryID = suggestion.category.id
        suggestionNote =
            "Suggested: \(suggestion.category.name) · \(Int((suggestion.confidence * 100).rounded()))% · \(suggestion.reason)"
    }

    public func press(_ key: String) {
        switch activeField {
            case .amount:
                if isAmountPristine, key != "⌫" {
                    amountText = ""
                }

                isAmountPristine = false
                AmountEntry.apply(key, to: &amountText, exponent: currency.exponent)

            case .fee:
                if isFeePristine, key != "⌫" {
                    feeText = ""
                }

                isFeePristine = false
                AmountEntry.apply(key, to: &feeText, exponent: currency.exponent)
        }
    }

    /// Flips the sign for adjustments and opening balances, whose sign is meaningful.
    /// The decimal keyboard has no minus key.
    public func toggleAmountSign() {
        guard supportsSignToggle else {
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

    // MARK: - Saving

    @discardableResult
    public func save(ledger: LedgerService) throws -> LedgerEntry {
        guard !isLinkedEntry else {
            throw EntryFormError.linkedEntry
        }

        guard isSupportedKind else {
            throw EntryFormError.unsupportedKind
        }

        guard let account = selectedAccount else {
            throw EntryFormError.missingAccount
        }

        guard let amount = parsedAmount, amount.minorUnits > 0 || supportsSignToggle else {
            throw EntryFormError.invalidAmount
        }

        if supportsSignToggle, amount.minorUnits == 0 {
            throw EntryFormError.invalidAmount
        }

        guard let feeMinor, feeMinor >= 0 else {
            throw EntryFormError.invalidAmount
        }

        let category = selectedCategoryForSave

        switch purpose {
            case .create:
                return try ledger.record(
                    kind: kind,
                    amountMinor: amount.minorUnits,
                    feeMinor: feeMinor,
                    account: account,
                    category: category,
                    payee: payee,
                    note: note,
                    occurredAt: occurredAt
                )

            case .edit, .review:
                guard let entry else {
                    throw EntryFormError.missingEntry
                }

                return try ledger.update(
                    entry,
                    kind: kind,
                    amountMinor: amount.minorUnits,
                    feeMinor: feeMinor,
                    account: account,
                    category: category,
                    payee: payee,
                    note: note,
                    occurredAt: occurredAt
                )
        }
    }

    private var selectedCategoryForSave: SpendingCategory? {
        // A hidden control means "not editable", never "clear it": ingest can attach a
        // category to a transfer row before it is reviewed.
        guard showsCategory else {
            return pinnedCategory
        }

        return availableCategories.first { $0.id == selectedCategoryID }
    }

    /// Plain editable text for a minor-unit amount, with no grouping or currency token.
    static func plainText(minorUnits: Int64, currency: Currency) -> String {
        let money = Money(minorUnits: minorUnits, currency: currency)
        return NSDecimalNumber(decimal: money.decimalValue).stringValue
    }
}

public enum EntryFormError: Error, Equatable, LocalizedError {
    case missingAccount
    case invalidAmount
    case linkedEntry
    case unsupportedKind
    case missingEntry

    public var errorDescription: String? {
        switch self {
            case .missingAccount:
                return "Choose an account for this entry."
            case .invalidAmount:
                return "Enter an amount greater than zero."
            case .linkedEntry:
                return "This entry belongs to a transfer, loan or investment. Change it from its own screen."
            case .unsupportedKind:
                return "This entry can't be edited here."
            case .missingEntry:
                return "This entry no longer exists."
        }
    }
}
