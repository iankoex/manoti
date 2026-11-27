//
//  TagDetailView.swift
//  TagsFeature
//

import AppModels
import AppServices
import LedgerFeature
import Modifiers
import SwiftUI

/// One tag's money and the entries behind it.
public struct TagDetailView: View {
    @Environment(TagService.self) private var tagService
    @Environment(AppService.self) private var appService

    private let tag: Tag

    @State private var summary: TagSummary?
    @State private var entries: [TaggedEntry] = []
    @State private var errorMessage: String?

    public init(tag: Tag) {
        self.tag = tag
    }

    public var body: some View {
        List {
            Section {
                totals
            }

            if let missing = summary?.missingRates, !missing.isEmpty {
                Section {
                    Label(
                        "No rate for \(missing.joined(separator: ", ")) — shown 1:1",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Transactions") {
                if entries.isEmpty {
                    Text("Nothing tagged yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { item in
                        NavigationLink {
                            LedgerEntryDetailView(entry: item.entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                LedgerEntryRowView(entry: item.entry)

                                if item.amountMinor != item.entry.amountMinor {
                                    HStack(spacing: 4) {
                                        Text("This tag:")
                                        AmountText(
                                            Money(minorUnits: item.amountMinor, currency: item.entry.currency),
                                            style: .caption
                                        )
                                        Text("of")
                                        AmountText(
                                            Money(
                                                minorUnits: item.entry.amountMinor,
                                                currency: item.entry.currency
                                            ),
                                            style: .caption
                                        )
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tag.name)
        .navigationBarTitleDisplayModeInlineCompat()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tag.isOpen ? "Close" : "Reopen") {
                    setStatus(close: tag.isOpen)
                }
            }
        }
        .alert(
            "Could not update tag",
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
        .task { reload() }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Text(tag.isOpen ? "Balance" : "Profit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !tag.isOpen, let closedAt = tag.closedAt {
                    Text("Closed \(closedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary {
                AmountText(
                    tag.isOpen ? summary.balance : summary.profit,
                    style: .system(size: 34, weight: .semibold, design: .rounded)
                )

                HStack(spacing: ManotiSpacing.medium) {
                    today("Received", summary.received, tint: ManotiColor.forHex("#27AE60"))
                    today("Spent", summary.spent, tint: ManotiColor.forHex("#EB5757"))
                }
            } else {
                Text("—")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if !tag.note.isEmpty {
                Text(tag.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func today(_ title: String, _ money: Money, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            AmountText(money, style: .subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
    }

    private func reload() {
        do {
            summary = try tagService.summary(for: tag, displayCurrency: appService.displayCurrency)
            entries = try tagService.entries(for: tag)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setStatus(close: Bool) {
        do {
            if close {
                try tagService.closeTag(tag)
            } else {
                try tagService.reopenTag(tag)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func navigationBarTitleDisplayModeInlineCompat() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
