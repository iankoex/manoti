//
//  HomeView.swift
//  NavigationFeature
//

import AccountsFeature
import AppModels
import AppPackageExtensions
import AppServices
import Charts
import LedgerFeature
import LoansFeature
import Modifiers
import SettingsFeature
import SwiftUI

public struct HomeView: View {
    private let onAdd: () -> Void

    @Environment(AppService.self) private var appService
    @Environment(PrivacyService.self) private var privacyService
    @Environment(AccountService.self) private var accountService
    @Environment(LedgerService.self) private var ledgerService
    @Environment(LoanService.self) private var loanService
    @Environment(InsightsService.self) private var insights

    @State private var accounts: [Account] = []
    @State private var recent: [LedgerEntry] = []
    @State private var netWorth: NetWorth?
    @State private var loanSummary: LoanSummary?
    @State private var weekTotal: PeriodTotal?
    @State private var monthTotal: PeriodTotal?
    @State private var dailySpend: [DailySpend] = []
    @State private var accountsRevision = 0

    public init(onAdd: @escaping () -> Void) {
        self.onAdd = onAdd
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                    NetWorthCard(netWorth: netWorth)

                    AccountsSection(accounts: activeAccounts, revision: accountsRevision)

                    LoansCard(summary: loanSummary)

                    if activeAccounts.isEmpty {
                        EmptyStateView(
                            symbolName: "wallet.bifold",
                            title: "Start with an account",
                            message: "Add a bank or mobile money account, then record your first expense."
                        )
                    } else {
                        TotalsRow(weekTotal: weekTotal, monthTotal: monthTotal)
                        SpendChartCard(days: dailySpend)
                        RecentSection(entries: recent)
                    }
                }
                .padding(.horizontal, ManotiSpacing.regular)
                .padding(.bottom, 88)
            }
            .background(.background)
            .navigationTitle("Manoti")
            .toolbar {
                SettingsToolbarItem()

                ToolbarItem(placement: eyePlacement) {
                    PrivacyToolbarButton(isHidden: privacyService.isAmountsHidden) {
                        togglePrivacy()
                    }
                }
            }
            .onManotiDataChange { reload() }
        }
    }

    private func togglePrivacy() {
        if privacyService.isAmountsHidden {
            privacyService.reveal()
        } else {
            privacyService.hide()
        }
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var eyePlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    private func reload() {
        accounts = (try? accountService.fetchAccounts()) ?? []
        recent = (try? ledgerService.recent(limit: 6)) ?? []
        accountsRevision += 1

        let currency = appService.displayCurrency

        do {
            netWorth = try insights.netWorth(accounts: activeAccounts, displayCurrency: currency)
            loanSummary = try loanService.summary(displayCurrency: currency)
            dailySpend = try insights.dailySpend(days: 7, displayCurrency: currency)

            var calendar = Calendar.current
            calendar.firstWeekday = appService.weekStartsOn
            let now = Date()

            if let week = calendar.dateInterval(of: .weekOfYear, for: now),
                let month = calendar.dateInterval(of: .month, for: now)
            {
                weekTotal = try insights.total(
                    kind: .expense,
                    from: week.start,
                    to: week.end,
                    displayCurrency: currency
                )
                monthTotal = try insights.total(
                    kind: .expense,
                    from: month.start,
                    to: month.end,
                    displayCurrency: currency
                )
            }
        } catch {
            netWorth = nil
            loanSummary = nil
            weekTotal = nil
            monthTotal = nil
            dailySpend = []
        }
    }
}

private struct NetWorthCard: View {
    let netWorth: NetWorth?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Net worth")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let netWorth {
                AmountText(netWorth.amount, style: .system(size: 40, weight: .semibold, design: .rounded))

                if !netWorth.missingRates.isEmpty {
                    Label(
                        "No rate for \(netWorth.missingRates.joined(separator: ", ")) — shown 1:1",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }
}

private struct AccountsSection: View {
    let accounts: [Account]
    let revision: Int

    var body: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            NavigationLink {
                AccountsView(embedded: true)
                    .navigationTitle("Accounts")
            } label: {
                HStack {
                    Text("Accounts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 3) {
                        Text(accounts.isEmpty ? "Add" : "See all")
                            .font(.caption.weight(.medium))

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accounts.isEmpty ? "Add your first account" : "See all accounts")

            if accounts.isEmpty {
                Text("No accounts yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(accounts) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                AccountChip(account: account, balance: account.balance)
                            }
                            .buttonStyle(.plain)
                            .id("\(account.id.uuidString)-\(account.balance.minorUnits)-\(revision)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }
}

private struct LoansCard: View {
    let summary: LoanSummary?

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        NavigationLink {
            LoansView()
        } label: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                HStack {
                    Text("Loans")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 3) {
                        Text("See all")
                            .font(.caption.weight(.medium))

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }

                if let summary {
                    HStack(spacing: ManotiSpacing.medium) {
                        LoanTotal(
                            title: "Owed to me",
                            money: summary.receivable,
                            tint: ManotiColor.forHex("#27AE60")
                        )

                        LoanTotal(
                            title: "I owe",
                            money: summary.payable,
                            tint: ManotiColor.forHex("#EB5757")
                        )
                    }

                    if summary.receivable.isZero && summary.payable.isZero {
                        Text("Lend or borrow to track who owes whom.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !summary.missingRates.isEmpty {
                        Label(
                            "No rate for \(summary.missingRates.joined(separator: ", ")) — shown 1:1",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                } else {
                    Text("—")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ManotiSpacing.regular)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let summary else {
            return "Loans, see all"
        }

        return
            "Loans, owed to me \(AmountMask.money(summary.receivable, hidden: amountsHidden)), I owe \(AmountMask.money(summary.payable, hidden: amountsHidden)), see all"
    }
}

private struct LoanTotal: View {
    let title: String
    let money: Money
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)

            AmountText(money, style: .subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TotalsRow: View {
    let weekTotal: PeriodTotal?
    let monthTotal: PeriodTotal?

    var body: some View {
        HStack(spacing: 12) {
            TotalCard(title: "This week", total: weekTotal, symbol: "calendar.day.timeline.left")
            TotalCard(title: "This month", total: monthTotal, symbol: "calendar")
        }
    }
}

private struct TotalCard: View {
    let title: String
    let total: PeriodTotal?
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let total {
                AmountText(total.amount, style: .headline)

                if !total.missingRates.isEmpty {
                    Label(
                        "No rate for \(total.missingRates.joined(separator: ", ")) — shown 1:1",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            } else {
                Text("—")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.medium)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 16))
    }
}

private struct SpendChartCard: View {
    let days: [DailySpend]

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if amountsHidden {
                AmountsHiddenPlaceholder()
                    .frame(height: 110)
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Spent", NSDecimalNumber(decimal: day.total.decimalValue).doubleValue)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
                .accessibilityLabel("Spending over the last seven days")
            }

            if !missingRates.isEmpty {
                Label(
                    "No rate for \(missingRates.joined(separator: ", ")) — shown 1:1",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var missingRates: [String] {
        Array(Set(days.flatMap(\.missingRates))).sorted()
    }
}

private struct RecentSection: View {
    let entries: [LedgerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("Nothing recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        LedgerEntryDetailView(entry: entry)
                    } label: {
                        LedgerEntryRowView(entry: entry)
                    }
                    .buttonStyle(.plain)

                    if entry.id != entries.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }
}
