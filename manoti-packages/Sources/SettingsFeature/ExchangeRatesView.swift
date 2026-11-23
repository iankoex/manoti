//
//  ExchangeRatesView.swift
//  SettingsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

struct ExchangeRatesView: View {
    @Environment(ExchangeRateService.self) private var exchangeRates

    @State private var summaries: [ExchangeRateSummary] = []
    @State private var isAdding = false
    @State private var pendingDeletion: ExchangeRateSummary?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if summaries.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(summaries) { summary in
                        RateRow(summary: summary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if summary.source == .manual {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        pendingDeletion = summary
                                    }
                                }
                            }
                    }
                } footer: {
                    Text(
                        "Conversions use the newest rate on or before the transaction date. Missing historical rates are shown 1:1 in major units and marked. Rates captured from transfers are kept as history and cannot be deleted."
                    )
                }
            }
        }
        .navigationTitle("Exchange rates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add rate", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            ExchangeRateEditorView()
        }
        .confirmationDialog(
            "Delete this rate?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePending)
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Balances will use the next newest rate for this pair.")
        }
        .alert(
            "Could not delete rate",
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

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("No exchange rates yet", systemImage: "arrow.left.arrow.right")
                    .font(.headline)

                Text("Add a rate to convert balances and insights into your display currency.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    isAdding = true
                } label: {
                    Label("Add a rate", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 8)
        }
    }

    private func reload() {
        summaries = (try? exchangeRates.latestRates()) ?? []
    }

    private func deletePending() {
        guard let summary = pendingDeletion else {
            return
        }

        pendingDeletion = nil

        do {
            try exchangeRates.deleteRate(id: summary.recordID)
        } catch {
            errorMessage = "This rate came from a transfer and is kept as history."
        }
    }
}

private struct RateRow: View {
    let summary: ExchangeRateSummary

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("1 \(summary.base.code)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("\(AmountMask.text(formattedRate, hidden: amountsHidden)) \(summary.quote.code)")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
            }

            Text("\(sourceLabel) · \(summary.asOf.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "1 \(summary.base.code) equals \(AmountMask.text(formattedRate, hidden: amountsHidden)) \(summary.quote.code), \(sourceLabel.lowercased())"
        )
    }

    private var formattedRate: String {
        let value = Decimal(summary.rate.rateScaled) / Decimal(FXRate.scale)
        return value.formatted(.number.precision(.fractionLength(2...6)))
    }

    private var sourceLabel: String {
        summary.source == .manual ? "Manual" : "From transfer"
    }
}
