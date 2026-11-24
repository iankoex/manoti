//
//  TransactionsView.swift
//  LedgerFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import SwiftUI

/// The full ledger, newest first, grouped by day with filters and incremental loading.
public struct TransactionsView: View {
    private static let pageSize = 50

    @Environment(AppService.self) private var appService
    @Environment(AccountService.self) private var accountService
    @Environment(LedgerService.self) private var ledgerService
    @Environment(InsightsService.self) private var insights

    @State private var entries: [LedgerEntry] = []
    @State private var accounts: [Account] = []
    @State private var filter = TransactionFilter()
    @State private var searchText = ""
    @State private var visibleCount = TransactionsView.pageSize
    @State private var rateBook: ExchangeRateBook?
    @State private var now = Date()
    @State private var isShowingFilters = false

    public init() {}

    public var body: some View {
        List {
            if filter.isActive {
                activeFilters
            }

            if filtered.isEmpty {
                emptyState
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink {
                                LedgerEntryDetailView(entry: entry)
                            } label: {
                                LedgerEntryRowView(entry: entry, dateStyle: .time)
                            }
                            .onAppear { loadMoreIfNeeded(entry) }
                        }
                    } header: {
                        Text(dayTitle(group.day))
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Text("\(filtered.count) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Transactions")
        .searchable(
            text: $searchText,
            placement: searchPlacement,
            prompt: "Search payee, note or account"
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingFilters = true
                } label: {
                    Label(
                        "Filter",
                        systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .accessibilityLabel(filter.isActive ? "Filter, active" : "Filter")
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            TransactionFilterView(
                filter: $filter,
                currency: appService.displayCurrency,
                accounts: accounts
            )
        }
        .onChange(of: filter) { _, _ in
            visibleCount = Self.pageSize
        }
        .onChange(of: searchText) { _, _ in
            visibleCount = Self.pageSize
        }
        .onManotiDataChange { reload() }
    }

    // MARK: - Filtering

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = appService.weekStartsOn
        return calendar
    }

    /// Hidden until the user scrolls to the top, the way a navigation drawer behaves.
    private var searchPlacement: SearchFieldPlacement {
        #if os(iOS)
        .navigationBarDrawer(displayMode: .automatic)
        #else
        .automatic
        #endif
    }

    private var filtered: [LedgerEntry] {
        TransactionFilterEngine.apply(
            entries,
            filter: filter,
            searchText: searchText,
            displayCurrency: appService.displayCurrency,
            rateBook: rateBook,
            now: now,
            calendar: calendar
        )
    }

    private var visible: [LedgerEntry] {
        Array(filtered.prefix(visibleCount))
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let entries: [LedgerEntry]

        var id: Date { day }
    }

    private var dayGroups: [DayGroup] {
        let grouped = Dictionary(grouping: visible) { entry in
            calendar.startOfDay(for: entry.occurredAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            DayGroup(
                day: day,
                entries: (grouped[day] ?? []).sorted { $0.occurredAt > $1.occurredAt }
            )
        }
    }

    private func loadMoreIfNeeded(_ entry: LedgerEntry) {
        guard visibleCount < filtered.count, entry.id == visible.last?.id else {
            return
        }

        visibleCount = min(visibleCount + Self.pageSize, filtered.count)
    }

    private func reload() {
        entries = (try? ledgerService.transactions()) ?? []
        accounts = (try? accountService.fetchAccounts(includeArchived: true)) ?? []
        rateBook = try? insights.rateBook()
        now = Date()
    }

    // MARK: - Chrome

    private var activeFilters: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AccountKind.allCases.filter { !filter.accountKinds.contains($0) }) { kind in
                        filterChip("No \(kind.displayName)", systemImage: "xmark") {
                            filter.accountKinds.insert(kind)
                        }
                    }

                    ForEach(
                        accounts.filter {
                            filter.accountKinds.contains($0.kind)
                                && !filter.accountIDs.isEmpty
                                && !filter.accountIDs.contains($0.id)
                        }
                    ) { account in
                        filterChip("No \(account.displayName)", systemImage: "xmark") {
                            var ids = filter.accountIDs
                            ids.insert(account.id)
                            filter.accountIDs = ids == Set(accounts.map(\.id)) ? [] : ids
                        }
                    }

                    if !amountFilterLabel.isEmpty {
                        filterChip(amountFilterLabel) {
                            filter.minimumAmountText = ""
                            filter.maximumAmountText = ""
                        }
                    }

                    if filter.datePreset != .any {
                        filterChip(filter.datePreset.title) {
                            filter.datePreset = .any
                        }
                    }

                    filterChip("Clear all", systemImage: "xmark") {
                        filter.reset()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var amountFilterLabel: String {
        let minimum = filter.minimumAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximum = filter.maximumAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = appService.displayCurrency.code

        if !minimum.isEmpty, !maximum.isEmpty {
            return "\(code) \(minimum)–\(maximum)"
        }

        if !minimum.isEmpty {
            return "\(code) ≥ \(minimum)"
        }

        if !maximum.isEmpty {
            return "\(code) ≤ \(maximum)"
        }

        return ""
    }

    private func filterChip(
        _ title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label(
                    entries.isEmpty ? "No transactions yet" : "No matches",
                    systemImage: entries.isEmpty ? "list.bullet.rectangle" : "magnifyingglass"
                )
            } description: {
                Text(
                    entries.isEmpty
                        ? "Record an entry and it will appear here."
                        : "Try a wider date range, another account type, or a different search."
                )
            } actions: {
                if !entries.isEmpty {
                    Button("Clear filters") {
                        filter.reset()
                        searchText = ""
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }

        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
