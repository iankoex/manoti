//
//  GoalEditorView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Sheet for adding or editing a savings goal.
struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SavingsService.self) private var savingsService
    @Environment(AccountService.self) private var accountService
    @Environment(AppService.self) private var appService

    private let goal: Goal?

    @State private var name: String
    @State private var targetText = ""
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var accountID: UUID?
    @State private var note: String
    @State private var isArchived: Bool
    @State private var accounts: [Account] = []
    @State private var errorMessage: String?

    init(goal: Goal?) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _hasTargetDate = State(initialValue: goal?.targetDate != nil)
        _targetDate = State(initialValue: goal?.targetDate ?? Date())
        _accountID = State(initialValue: goal?.account?.id)
        _note = State(initialValue: goal?.note ?? "")
        _isArchived = State(initialValue: goal?.isArchived ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)

                    LabeledContent("Target") {
                        HStack(spacing: ManotiSpacing.small) {
                            Text(currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $targetText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    if let message = validationMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else {
                        Text("Progress comes from the linked account's balance.")
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

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if goal != nil {
                    Section {
                        Toggle("Archived", isOn: $isArchived)
                    }
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
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

                if let goal, targetText.isEmpty {
                    targetText =
                        NSDecimalNumber(
                            decimal: Money(minorUnits: goal.targetMinor, currency: currency).decimalValue
                        ).stringValue
                }
            }
        }
    }

    private var currency: Currency {
        goal?.currency ?? appService.displayCurrency
    }

    private var targetMinor: Int64? {
        MoneyParser.parse(targetText, defaultCurrency: currency)?.money.minorUnits
    }

    private var validationMessage: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let targetMinor, targetMinor >= 0 else {
            return "Enter a valid target."
        }

        return nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && targetMinor != nil
            && validationMessage == nil
    }

    private func save() {
        guard let targetMinor else {
            return
        }

        do {
            if let goal {
                try savingsService.updateGoal(
                    goal,
                    name: name,
                    targetMinor: targetMinor,
                    targetDate: hasTargetDate ? targetDate : nil,
                    currencyCode: currency.code,
                    account: accounts.first { $0.id == accountID },
                    note: note,
                    isArchived: isArchived
                )
            } else {
                try savingsService.createGoal(
                    name: name,
                    targetMinor: targetMinor,
                    targetDate: hasTargetDate ? targetDate : nil,
                    currencyCode: appService.displayCurrency.code,
                    account: accounts.first { $0.id == accountID },
                    note: note
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
