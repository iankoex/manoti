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

    public let purpose: Purpose
    public let entry: LedgerEntry?

    public var kind: LedgerEntryKind
    public var amountText = ""
    public var feeText = ""
    public var note = ""
    public var payee = ""
    /// The biller or aggregator behind the payee, e.g. "Family Bank Pesa Pap". Read-only.
    public var channelName = ""
    public var occurredAt: Date
    public var selectedAccountID: UUID?
    /// The other side of a transfer: the destination for an expense/out entry, the source
    /// for an income/in entry.
    public var counterpartAccountID: UUID?
    /// The amount on the other side when the two accounts use different currencies.
    public var counterpartAmountText = ""
    public var selectedCategoryID: UUID?
    /// Tags on the single line, or the tag set carried into the split editor.
    public var selectedTagIDs: Set<UUID> = []
    /// Non-nil while the split editor is open.
    public var lineDrafts: [LineDraft]?
    /// Expense, Income or Transfer in Review and Edit. Kept in step with `kind`.
    public var type: EntryFormType = .expense

    public var accounts: [Account] = []
    /// Every active account, including other currencies, for a transfer's counterpart.
    public var allAccounts: [Account] = []
    public var groups: [CategoryGroup] = []
    public var categories: [SpendingCategory] = []
    public var availableTags: [Tag] = []

    /// Kept for the review screen's caption. Informational only.
    public var suggestionNote: String?

    private let pinnedCategory: SpendingCategory?

    public init(
        purpose: Purpose = .create,
        entry: LedgerEntry? = nil,
        accounts: [Account] = [],
        groups: [CategoryGroup] = [],
        categories: [SpendingCategory] = [],
        tags: [Tag] = []
    ) {
        self.purpose = purpose
        self.entry = entry
        self.kind = entry?.kind ?? .expense
        self.type = Self.formType(for: entry?.kind ?? .expense)
        self.occurredAt = entry?.occurredAt ?? .now
        self.payee = entry?.payee ?? ""
        self.channelName = entry?.channelName ?? ""
        self.note = entry?.note ?? ""
        self.selectedAccountID = entry?.account?.id
        self.selectedCategoryID = entry?.orderedLines.first?.category?.id
        self.pinnedCategory = entry?.orderedLines.first?.category

        if let entry {
            amountText = Self.plainText(minorUnits: entry.amountMinor, currency: entry.currency)
            feeText = entry.feeMinor == 0 ? "" : Self.plainText(minorUnits: entry.feeMinor, currency: entry.currency)

            let lines = entry.orderedLines
            if lines.count > 1 {
                lineDrafts = lines.map { line in
                    LineDraft(
                        amountText: Self.plainText(minorUnits: line.amountMinor, currency: entry.currency),
                        categoryID: line.category?.id,
                        tagIDs: Set(line.tagList.map(\.id))
                    )
                }
            }

            selectedTagIDs = Set(lines.first?.tagList.map(\.id) ?? [])
        }

        if !accounts.isEmpty || !groups.isEmpty || !categories.isEmpty || !tags.isEmpty {
            setOptions(accounts: accounts, groups: groups, categories: categories, tags: tags)
        }
    }

    // MARK: - Options

    public func setOptions(
        accounts: [Account],
        groups: [CategoryGroup],
        categories: [SpendingCategory],
        tags: [Tag] = []
    ) {
        self.availableTags = tags

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

        self.allAccounts =
            accounts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }

                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        if let counterpartAccountID,
            !self.allAccounts.contains(where: { $0.id == counterpartAccountID })
        {
            self.counterpartAccountID = nil
        }

        self.groups = groups

        var all = categories
        // Keep an archived or otherwise unlisted current category selectable, so a save
        // with no interaction never silently clears categorisation.
        for category in entry?.orderedLines.compactMap(\.category) ?? [] {
            if !all.contains(where: { $0.id == category.id }) {
                all.append(category)
            }
        }

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

    public func reload(
        accountService: AccountService,
        categoryService: CategoryService,
        tagService: TagService? = nil
    ) {
        let accounts = (try? accountService.fetchAccounts()) ?? []
        let groups = (try? categoryService.fetchGroups()) ?? []
        let tags = (try? tagService?.fetchTags(includeClosed: true)) ?? []
        setOptions(
            accounts: accounts,
            groups: groups,
            categories: groups.flatMap(\.visibleCategories),
            tags: tags
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

    /// Review and Edit may switch Expense, Income and Transfer. Add has its own shell, and a
    /// linked entry belongs to its feature.
    public var isTypeEditable: Bool {
        guard purpose != .create, !isLinkedEntry else {
            return false
        }

        switch kind {
            case .expense, .income, .transferOut, .transferIn:
                return true
            default:
                return false
        }
    }

    public var typeOptions: [EntryFormType] {
        [.expense, .income, .transfer]
    }

    public var isTransferForm: Bool {
        isTypeEditable && type == .transfer
    }

    public var convertsToTransfer: Bool {
        isTransferForm
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

    /// Category has no effect on a transfer leg, loan, investment, adjustment or opening
    /// balance: only expenses and incomes carry lines.
    public var showsCategory: Bool {
        guard !isLinkedEntry else {
            return false
        }

        if isTypeEditable {
            return type != .transfer
        }

        return kind == .expense || kind == .income
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

    // MARK: - Transfer draft

    public var counterpartAccount: Account? {
        allAccounts.first { $0.id == counterpartAccountID }
    }

    /// The known side's account is `selectedAccount`. An expense is the source; an income is
    /// the destination.
    public var transferSourceAccount: Account? {
        kind == .transferOut ? selectedAccount : counterpartAccount
    }

    public var transferDestinationAccount: Account? {
        kind == .transferIn ? selectedAccount : counterpartAccount
    }

    public var transferSourceID: UUID? {
        kind == .transferOut ? selectedAccountID : counterpartAccountID
    }

    public var transferDestinationID: UUID? {
        kind == .transferIn ? selectedAccountID : counterpartAccountID
    }

    /// Selecting an account on the From side is always allowed. If it is the account the
    /// To side currently holds, To is cleared and this side takes it.
    public func selectTransferSource(_ accountID: UUID) {
        if kind == .transferOut {
            if counterpartAccountID == accountID {
                counterpartAccountID = nil
            }

            selectedAccountID = accountID
        } else {
            if selectedAccountID == accountID {
                selectedAccountID = nil
            }

            counterpartAccountID = accountID
        }
    }

    /// Selecting on the To side never takes the From account: the view disables that card,
    /// and this method leaves the source alone if it is called anyway.
    public func selectTransferDestination(_ accountID: UUID) {
        if kind == .transferIn {
            guard counterpartAccountID != accountID else {
                return
            }

            selectedAccountID = accountID
        } else {
            guard selectedAccountID != accountID else {
                return
            }

            counterpartAccountID = accountID
        }
    }

    /// Accounts the known side may use. They share the entry's currency. The account chosen
    /// for the other side stays in the list and is disabled by the view, so the user can
    /// still change this side without losing an option.
    public var knownSideAccounts: [Account] {
        accounts
    }

    /// Accounts the missing side may use, including another currency.
    public var counterpartAccounts: [Account] {
        allAccounts
    }

    public var transferAmountLabel: String {
        kind == .transferOut ? "Amount sent" : "Amount received"
    }

    public var transferCounterpartAmountLabel: String {
        kind == .transferOut ? "Amount received" : "Amount sent"
    }

    public var transferNeedsCounterpartAmount: Bool {
        guard isTransferForm, let source = transferSourceAccount,
            let destination = transferDestinationAccount
        else {
            return false
        }

        return source.currency != destination.currency
    }

    public var transferCounterpartCurrency: Currency {
        let account = kind == .transferOut ? transferDestinationAccount : transferSourceAccount
        return account?.currency ?? currency
    }

    public var transferFeeCurrency: Currency {
        transferSourceAccount?.currency ?? currency
    }

    public var parsedCounterpartAmount: Money? {
        MoneyParser.parse(
            counterpartAmountText,
            defaultCurrency: transferCounterpartCurrency
        )?.money
    }

    /// A transfer's fee lives on the out-leg, so it is parsed in the source currency.
    public var transferFeeMinor: Int64? {
        if feeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 0
        }

        return MoneyParser.parse(feeText, defaultCurrency: transferFeeCurrency)?.money.minorUnits
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

    // MARK: - Tags and split lines

    public var isSplit: Bool {
        lineDrafts != nil
    }

    public func tagObjects(for ids: Set<UUID>) -> [Tag] {
        availableTags.filter { ids.contains($0.id) }
    }

    public var selectedTags: [Tag] {
        tagObjects(for: selectedTagIDs)
    }

    public var linesTotalMinor: Int64 {
        (lineDrafts ?? []).reduce(Int64(0)) { total, draft in
            total + (MoneyParser.parse(draft.amountText, defaultCurrency: currency)?.money.minorUnits ?? 0)
        }
    }

    /// What is left of the entry total after the lines.
    public var splitRemainderMinor: Int64 {
        (parsedAmount?.minorUnits ?? 0) - linesTotalMinor
    }

    public var splitValidationMessage: String? {
        guard let drafts = lineDrafts, !drafts.isEmpty else {
            return nil
        }

        for draft in drafts {
            guard let minor = MoneyParser.parse(draft.amountText, defaultCurrency: currency)?.money.minorUnits,
                minor > 0
            else {
                return "Every line needs an amount greater than zero."
            }

            if let categoryID = draft.categoryID,
                let category = categories.first(where: { $0.id == categoryID }),
                category.kind != kind.categoryKind
            {
                return "Choose a category that matches this entry kind."
            }
        }

        guard linesTotalMinor == (parsedAmount?.minorUnits ?? 0) else {
            let total = Money(minorUnits: linesTotalMinor, currency: currency).formatted()
            let entry = Money(minorUnits: parsedAmount?.minorUnits ?? 0, currency: currency).formatted()
            return "The lines add up to \(total), but the entry is \(entry)."
        }

        return nil
    }

    public func toggleTag(_ tagID: UUID) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
    }

    public func toggleTag(_ tagID: UUID, onLine lineID: UUID) {
        guard let index = lineDrafts?.firstIndex(where: { $0.id == lineID }) else {
            return
        }

        if lineDrafts?[index].tagIDs.contains(tagID) == true {
            lineDrafts?[index].tagIDs.remove(tagID)
        } else {
            lineDrafts?[index].tagIDs.insert(tagID)
        }
    }

    public func beginSplit() {
        guard showsCategory, !isSplit else {
            return
        }

        let amount = parsedAmount?.minorUnits ?? 0
        lineDrafts = [
            LineDraft(
                amountText: amount == 0 ? "" : Self.plainText(minorUnits: amount, currency: currency),
                categoryID: selectedCategoryID,
                tagIDs: selectedTagIDs
            )
        ]
    }

    public func endSplit() {
        guard let first = lineDrafts?.first else {
            return
        }

        selectedCategoryID = first.categoryID
        selectedTagIDs = first.tagIDs
        lineDrafts = nil
    }

    /// Adds an empty line. The caller focuses it, so typing goes straight in.
    @discardableResult
    public func addLine() -> UUID? {
        guard isSplit else {
            return nil
        }

        let draft = LineDraft()
        lineDrafts?.append(draft)
        return draft.id
    }

    public func removeLine(_ id: UUID) {
        guard let drafts = lineDrafts, drafts.count > 1 else {
            return
        }

        lineDrafts = drafts.filter { $0.id != id }
    }

    /// Puts what is left of the entry on a line of its own. An empty last line is filled
    /// instead of appending, so pressing the two buttons in either order never duplicates it.
    /// Replaces the lines with the proportions remembered for this merchant, sized to the
    /// entry. Missing categories drop out and the remaining shares are renormalised.
    public func applySplitTemplate(_ template: SplitTemplate) {
        guard showsCategory, let total = parsedAmount?.minorUnits, total > 0 else {
            return
        }

        let known = template.lines.filter { line in
            categories.contains { $0.id == line.categoryID }
        }

        guard let filtered = SplitTemplate(lines: known),
            let allocations = filtered.allocations(totalMinor: total)
        else {
            return
        }

        lineDrafts = allocations.map { allocation in
            LineDraft(
                amountText: Self.plainText(minorUnits: allocation.amountMinor, currency: currency),
                categoryID: allocation.categoryID
            )
        }
    }

    public func addRemainderLine() -> UUID? {
        guard isSplit, splitRemainderMinor > 0 else {
            return nil
        }

        let amount = Self.plainText(minorUnits: splitRemainderMinor, currency: currency)

        if let lastIndex = lineDrafts?.indices.last,
            let last = lineDrafts?[lastIndex],
            last.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lineDrafts?[lastIndex].amountText = amount
            return last.id
        }

        let draft = LineDraft(amountText: amount)
        lineDrafts?.append(draft)
        return draft.id
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

        if isTransferForm {
            return transferValidationMessage
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

        if let splitMessage = splitValidationMessage {
            return splitMessage
        }

        return nil
    }

    private var transferValidationMessage: String? {
        guard let source = transferSourceAccount else {
            return accounts.isEmpty ? "No active accounts available." : "Choose the source account."
        }

        guard let destination = transferDestinationAccount else {
            return "Choose the destination account."
        }

        guard source.id != destination.id else {
            return "Choose two different accounts."
        }

        guard let amount = parsedAmount else {
            return "Enter a valid amount."
        }

        guard amount.minorUnits > 0 else {
            return "Enter an amount greater than zero."
        }

        guard let fee = transferFeeMinor, fee >= 0 else {
            return "Enter a fee of zero or more."
        }

        if source.currency != destination.currency {
            guard let counterpart = parsedCounterpartAmount, counterpart.minorUnits > 0 else {
                return "Enter the \(transferCounterpartAmountLabel.lowercased())."
            }
        }

        return nil
    }

    public var canSave: Bool {
        validationMessage == nil
    }

    /// The conversion removes split lines and tags. The host asks before discarding them.
    public var conversionDropsSplitOrTags: Bool {
        guard convertsToTransfer else {
            return false
        }

        return isSplit || (entry?.orderedLines.count ?? 0) > 1
            || !selectedTagIDs.isEmpty
            || (entry?.orderedLines.contains { !$0.tagList.isEmpty } ?? false)
    }

    // MARK: - Editing

    public func setKind(_ kind: LedgerEntryKind) {
        let current = availableCategories.first { $0.id == selectedCategoryID }
        self.kind = kind
        self.type = Self.formType(for: kind)

        if kind != .expense, kind != .income {
            lineDrafts = nil
        }

        if kind != .transferOut, kind != .transferIn {
            counterpartAccountID = nil
            counterpartAmountText = ""
        }

        if let current, current.kind != kind.categoryKind {
            selectedCategoryID = nil
        }
    }

    /// Switches the form between Expense, Income and Transfer. Nothing is written until Save
    /// or Confirm, so switching back and forth is free.
    public func setType(_ type: EntryFormType) {
        guard purpose != .create else {
            return
        }

        switch type {
            case .transfer:
                let wasInbound = kind == .income || kind == .transferIn
                self.type = .transfer
                kind = wasInbound ? .transferIn : .transferOut
                // Keep split drafts so switching back does not silently lose them. The
                // split UI is hidden while the type is Transfer; conversion discards the
                // lines only after the warning.
                counterpartAmountText = ""
            case .expense:
                setKind(.expense)
            case .income:
                setKind(.income)
        }
    }

    nonisolated static func formType(for kind: LedgerEntryKind) -> EntryFormType {
        switch kind {
            case .income: .income
            case .transferOut, .transferIn: .transfer
            default: .expense
        }
    }

    public func applySuggestion(_ suggestion: CategorySuggestion?) {
        guard purpose == .review, entry?.orderedLines.first?.category == nil, let suggestion else {
            return
        }

        selectedCategoryID = suggestion.category.id
        suggestionNote =
            "Suggested: \(suggestion.category.name) · \(Int((suggestion.confidence * 100).rounded()))% · \(suggestion.reason)"
    }

    /// Keeps an amount field numeric: digits, one decimal separator and, when allowed, a
    /// leading minus. Hardware keyboards and paste can otherwise put letters in the field.
    public static func sanitisedAmountText(
        _ raw: String,
        exponent: Int,
        allowsNegative: Bool = false
    ) -> String {
        AmountEntry.sanitisedText(raw, exponent: exponent, allowsNegative: allowsNegative)
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

    /// Saves whichever type the form currently shows. A transfer converts the existing entry
    /// into one leg and creates the other; the rest follows the ordinary ledger path.
    @discardableResult
    public func save(ledger: LedgerService, transfer: TransferService) throws -> LedgerEntry {
        if convertsToTransfer {
            return try convertToTransfer(service: transfer)
        }

        return try save(ledger: ledger)
    }

    @discardableResult
    private func convertToTransfer(service: TransferService) throws -> LedgerEntry {
        guard let entry else {
            throw EntryFormError.missingEntry
        }

        guard let source = transferSourceAccount, let destination = transferDestinationAccount else {
            throw EntryFormError.missingTransferAccount
        }

        guard source.id != destination.id else {
            throw EntryFormError.sameTransferAccount
        }

        guard let knownAmount = parsedAmount, knownAmount.minorUnits > 0 else {
            throw EntryFormError.invalidAmount
        }

        let amountOut: Int64
        let amountIn: Int64

        if kind == .transferOut {
            amountOut = knownAmount.minorUnits
            amountIn =
                source.currency == destination.currency
                ? amountOut
                : (parsedCounterpartAmount?.minorUnits ?? 0)
        } else {
            amountIn = knownAmount.minorUnits
            amountOut =
                source.currency == destination.currency
                ? amountIn
                : (parsedCounterpartAmount?.minorUnits ?? 0)
        }

        guard amountOut > 0, amountIn > 0, let fee = transferFeeMinor, fee >= 0 else {
            throw EntryFormError.invalidAmount
        }

        _ = try service.convert(
            entry: entry,
            source: source,
            destination: destination,
            amountOutMinor: amountOut,
            amountInMinor: amountIn,
            feeMinor: fee,
            occurredAt: occurredAt,
            payee: payee,
            note: note
        )

        kind = entry.kind
        type = .transfer
        return entry
    }

    @discardableResult
    public func save(ledger: LedgerService) throws -> LedgerEntry {
        guard !convertsToTransfer else {
            // The transfer path needs the other leg; use `save(ledger:transfer:)`.
            throw EntryFormError.unsupportedKind
        }

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
        let lines = lineInputs(for: amount.minorUnits, category: category)

        switch purpose {
            case .create:
                return try ledger.record(
                    kind: kind,
                    amountMinor: amount.minorUnits,
                    feeMinor: feeMinor,
                    account: account,
                    lines: lines,
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
                    lines: lines,
                    payee: payee,
                    note: note,
                    occurredAt: occurredAt
                )
        }
    }

    private func lineInputs(for amountMinor: Int64, category: SpendingCategory?) -> [LedgerLineInput] {
        guard kind == .expense || kind == .income else {
            return []
        }

        if let drafts = lineDrafts {
            return drafts.compactMap { draft in
                guard let minor = MoneyParser.parse(draft.amountText, defaultCurrency: currency)?.money.minorUnits,
                    minor > 0
                else {
                    return nil
                }

                return LedgerLineInput(
                    amountMinor: minor,
                    category: categories.first { $0.id == draft.categoryID },
                    tags: tagObjects(for: draft.tagIDs)
                )
            }
        }

        return [LedgerLineInput(amountMinor: amountMinor, category: category, tags: selectedTags)]
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
    case missingTransferAccount
    case sameTransferAccount
    case invalidAmount
    case linkedEntry
    case unsupportedKind
    case missingEntry

    public var errorDescription: String? {
        switch self {
            case .missingAccount:
                return "Choose an account for this entry."
            case .missingTransferAccount:
                return "Choose both accounts for this transfer."
            case .sameTransferAccount:
                return "Choose two different accounts."
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
