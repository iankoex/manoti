//
//  SinkingFundEditorView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for adding or editing a sinking fund.
struct SinkingFundEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SavingsService.self) private var savingsService
    @Environment(AccountService.self) private var accountService
    @Environment(CategoryService.self) private var categoryService
    @Environment(AppService.self) private var appService

    private let fund: SinkingFund?

    @State private var name: String
    @State private var targetText: String
    @State private var monthlyText: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var note: String
    @State private var isArchived: Bool
    @State private var accounts: [Account] = []
    @State private var categories: [SpendingCategory] = []
    @State private var errorMessage: String?

    init(fund: SinkingFund?) {
        self.fund = fund
        _name = State(initialValue: fund?.name ?? "")
        _targetText = State(initialValue: "")
        _monthlyText = State(initialValue: "")
        _hasTargetDate = State(initialValue: fund?.targetDate != nil)
        _targetDate = State(initialValue: fund?.targetDate ?? Date())
        _accountID = State(initialValue: fund?.account?.id)
        _categoryID = State(initialValue: fund?.category?.id)
        _note = State(initialValue: fund?.note ?? "")
        _isArchived = State(initialValue: fund?.isArchived ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Target") {
                        amountField($targetText)
                    }
                    LabeledContent("Monthly set-aside") {
                        amountField($monthlyText)
                    }
                } footer: {
                    if let message = validationMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else {
                        Text("Amounts are in \(appService.displayCurrency.code).")
                    }
                }

                Section("Details") {
                    Toggle("Target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                    }

                    Picker("Account", selection: $accountID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(accounts) { account in
                            Text(account.displayName).tag(Optional(account.id))
                        }
                    }

                    Picker("Category", selection: $categoryID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if fund != nil {
                    Section {
                        Toggle("Archived", isOn: $isArchived)
                    } footer: {
                        Text("Archived funds keep their contributions.")
                    }
                }
            }
            .navigationTitle(fund == nil ? "New sinking fund" : "Edit fund")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                }
            }
            .alert(
                "Could not save",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                accounts =
                    (try? accountService.fetchAccounts())?.filter {
                        !$0.isArchived && $0.currencyCode == currency.code
                    } ?? []
                categories = (try? categoryService.fetchCategories(kind: .expense)) ?? []

                if let fund, targetText.isEmpty {
                    targetText = Self.editableText(fund.targetMinor, currency: currency)
                }

                if let fund, monthlyText.isEmpty, fund.monthlyAccrualMinor != 0 {
                    monthlyText = Self.editableText(fund.monthlyAccrualMinor, currency: currency)
                }
            }
        }
    }

    private var currency: Currency {
        fund?.currency ?? appService.displayCurrency
    }

    private var targetMinor: Int64? {
        MoneyParser.parse(targetText, defaultCurrency: currency)?.money.minorUnits
    }

    private var monthlyMinor: Int64? {
        guard !monthlyText.isEmpty else {
            return 0
        }

        return MoneyParser.parse(monthlyText, defaultCurrency: currency)?.money.minorUnits
    }

    private var validationMessage: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let targetMinor, targetMinor >= 0 else {
            return "Enter a valid target."
        }

        guard let monthlyMinor, monthlyMinor >= 0 else {
            return "Enter a valid monthly amount."
        }

        return nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && targetMinor != nil
            && monthlyMinor != nil
            && validationMessage == nil
    }

    private func save() {
        guard let targetMinor, let monthlyMinor else {
            return
        }

        do {
            if let fund {
                try savingsService.updateFund(
                    fund,
                    name: name,
                    targetMinor: targetMinor,
                    monthlyAccrualMinor: monthlyMinor,
                    targetDate: hasTargetDate ? targetDate : nil,
                    currencyCode: currency.code,
                    category: categories.first { $0.id == categoryID },
                    account: accounts.first { $0.id == accountID },
                    note: note,
                    isArchived: isArchived
                )
            } else {
                try savingsService.createFund(
                    name: name,
                    targetMinor: targetMinor,
                    monthlyAccrualMinor: monthlyMinor,
                    targetDate: hasTargetDate ? targetDate : nil,
                    currencyCode: currency.code,
                    category: categories.first { $0.id == categoryID },
                    account: accounts.first { $0.id == accountID },
                    note: note
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func amountField(_ text: Binding<String>) -> some View {
        HStack(spacing: ManotiSpacing.small) {
            Text(currency.code)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("0.00", text: text)
                .decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private static func editableText(_ minorUnits: Int64, currency: Currency) -> String {
        NSDecimalNumber(decimal: Money(minorUnits: minorUnits, currency: currency).decimalValue).stringValue
    }
}
