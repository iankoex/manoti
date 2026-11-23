//
//  SinkingFundDetailView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// One sinking fund with its contribution history.
struct SinkingFundDetailView: View {
    let fund: SinkingFund

    @Environment(\.dismiss) private var dismiss
    @Environment(SavingsService.self) private var savingsService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var contributions: [SinkingFundContribution] = []
    @State private var isEditing = false
    @State private var isAddingContribution = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fund.name)
                        .font(.headline)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        MaskedAmountText(
                            fund.funded,
                            style: .title2.weight(.semibold)
                        )
                        Text("of")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MaskedAmountText(fund.target, style: .subheadline)
                    }

                    if let fraction = SavingsFormatting.progressFraction(
                        fundedMinor: fund.fundedMinor,
                        targetMinor: fund.targetMinor
                    ) {
                        ProgressView(value: amountsHidden ? 0 : fraction)
                            .tint(.accentColor)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                if let targetDate = fund.targetDate {
                    LabeledContent("Target date") {
                        Text(targetDate, format: .dateTime.day().month(.abbreviated).year())
                    }
                }

                if fund.monthlyAccrualMinor > 0 {
                    LabeledContent("Monthly set-aside") {
                        MaskedAmountText(
                            Money(minorUnits: fund.monthlyAccrualMinor, currency: fund.currency),
                            style: .subheadline
                        )
                    }
                }

                if let account = fund.account {
                    LabeledContent("Account", value: account.displayName)
                }

                if let category = fund.category {
                    LabeledContent("Category", value: category.name)
                }

                if !fund.note.isEmpty {
                    LabeledContent("Note") {
                        Text(fund.note)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Contributions") {
                if contributions.isEmpty {
                    Text("No contributions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contributions) { contribution in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                MaskedAmountText(contribution.amount, style: .subheadline.weight(.medium))

                                Text(
                                    contribution.occurredAt,
                                    format: .dateTime.day().month(.abbreviated).year()
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let account = contribution.account {
                                Text(account.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(contribution)
                            }
                        }
                    }
                }

                Button("Add contribution", systemImage: "plus.circle") {
                    isAddingContribution = true
                }
            }
        }
        .navigationTitle("Sinking fund")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit fund", systemImage: "pencil") {
                        isEditing = true
                    }

                    Button(fund.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                        setArchived(!fund.isArchived)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            SinkingFundEditorView(fund: fund)
        }
        .sheet(isPresented: $isAddingContribution) {
            ContributionEditorView(fund: fund)
        }
        .alert(
            "Could not update the fund",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onManotiDataChange { reload() }
    }

    private func reload() {
        contributions = savingsService.contributions(for: fund)
    }

    private func delete(_ contribution: SinkingFundContribution) {
        do {
            try savingsService.deleteContribution(contribution)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setArchived(_ archived: Bool) {
        do {
            try savingsService.updateFund(
                fund,
                name: fund.name,
                targetMinor: fund.targetMinor,
                monthlyAccrualMinor: fund.monthlyAccrualMinor,
                targetDate: fund.targetDate,
                currencyCode: fund.currencyCode,
                category: fund.category,
                account: fund.account,
                note: fund.note,
                isArchived: archived
            )

            if archived {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ContributionEditorView: View {
    let fund: SinkingFund

    @Environment(\.dismiss) private var dismiss
    @Environment(SavingsService.self) private var savingsService
    @Environment(AccountService.self) private var accountService
    @Environment(AppService.self) private var appService

    @State private var amountText = ""
    @State private var occurredAt = Date()
    @State private var accountID: UUID?
    @State private var note = ""
    @State private var accounts: [Account] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: ManotiSpacing.small) {
                        Text(fund.currency.code)
                            .foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText)
                            .decimalKeyboard()
                            .monospacedDigit()
                    }

                    DatePicker("Date", selection: $occurredAt, displayedComponents: .date)

                    Picker("Account", selection: $accountID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(accounts) { account in
                            Text(account.displayName).tag(Optional(account.id))
                        }
                    }
                }

                Section {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Add contribution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(parsedAmount == nil)
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
                accounts = (try? accountService.fetchAccounts())?.filter { !$0.isArchived } ?? []
                accountID = fund.account?.id
            }
        }
    }

    private var parsedAmount: Money? {
        guard let parsed = MoneyParser.parse(amountText, defaultCurrency: fund.currency)?.money,
            parsed.minorUnits > 0
        else {
            return nil
        }

        return parsed
    }

    private func save() {
        guard let parsedAmount else {
            return
        }

        do {
            try savingsService.addContribution(
                to: fund,
                amountMinor: parsedAmount.minorUnits,
                occurredAt: occurredAt,
                account: accounts.first { $0.id == accountID },
                note: note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
