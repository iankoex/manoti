//
//  BudgetView.swift
//  BudgetFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// The Plan tab's budget dashboard, pushed without its own navigation stack.
public struct BudgetView: View {
    @Environment(AppService.self) private var appService
    @Environment(BudgetService.self) private var budgetService

    @State private var kind: BudgetPeriodKind = .month
    @State private var period: BudgetPeriod?
    @State private var summary: BudgetSummary?
    @State private var safeToSpend: SafeToSpend?
    @State private var envelopes: [Envelope] = []
    @State private var editorTarget: EnvelopeEditorTarget?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                periodSwitcher
                periodHeader

                if let summary {
                    if summary.envelopes.isEmpty {
                        BudgetEmptyStateView(kind: kind, onSetUp: presentNewEnvelope)
                    } else {
                        BudgetSummaryCard(summary: summary, safeToSpend: safeToSpend)
                        envelopeList(summary.envelopes)
                    }
                } else if errorMessage == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, ManotiSpacing.extraLarge)
                }
            }
            .padding(.horizontal, ManotiSpacing.regular)
            .padding(.bottom, 88)
        }
        .background(.background)
        .navigationTitle("Budget")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: presentNewEnvelope) {
                    Label("Add envelope", systemImage: "plus")
                }
                .disabled(period == nil || summary == nil)
            }
        }
        .sheet(item: $editorTarget) { target in
            EnvelopeEditorView(period: target.period, envelope: target.envelope)
        }
        .alert(
            "Could not load the budget",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: kind) { _, _ in reload() }
        .onManotiDataChange { reload() }
    }

    private var periodSwitcher: some View {
        Picker("Period", selection: $kind) {
            ForEach(BudgetPeriodKind.allCases) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var periodHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(periodTitle)
                .font(.title2.weight(.semibold))

            if let period {
                Text(
                    "\(period.startDate.formatted(date: .abbreviated, time: .omitted)) – \(periodLastDay(period).formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The subtitle carries the date range, so a week is named rather than repeating it.
    private var periodTitle: String {
        guard let period, kind == .month else {
            return kind == .month ? "This month" : "This week"
        }

        return BudgetFormatting.periodTitle(
            kind: kind,
            startDate: period.startDate,
            calendar: calendar
        )
    }

    private func envelopeList(_ rows: [EnvelopeSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ManotiSpacing.small) {
                Text("Envelopes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(rows.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ManotiSpacing.small)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: .capsule)

                Spacer()
            }
            .padding(.bottom, ManotiSpacing.small)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    presentEditor(for: row.envelopeID)
                } label: {
                    EnvelopeRowView(row: row)
                }
                .buttonStyle(.plain)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = appService.weekStartsOn
        return calendar
    }

    private func periodLastDay(_ period: BudgetPeriod) -> Date {
        calendar.date(byAdding: .day, value: -1, to: period.endDate) ?? period.endDate
    }

    private func presentNewEnvelope() {
        guard let period else {
            return
        }

        editorTarget = EnvelopeEditorTarget(period: period, envelope: nil)
    }

    private func presentEditor(for envelopeID: UUID) {
        guard let period, let envelope = envelopes.first(where: { $0.id == envelopeID }) else {
            return
        }

        editorTarget = EnvelopeEditorTarget(period: period, envelope: envelope)
    }

    private func reload() {
        do {
            let period = try budgetService.currentPeriod(
                kind: kind,
                containing: Date.now,
                calendar: calendar
            )
            let displayCurrency = appService.displayCurrency

            self.period = period
            summary = try budgetService.summary(for: period, displayCurrency: displayCurrency)
            safeToSpend = try budgetService.safeToSpend(for: period, displayCurrency: displayCurrency)
            envelopes = try budgetService.envelopes(for: period)
            errorMessage = nil
        } catch {
            summary = nil
            safeToSpend = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct EnvelopeEditorTarget: Identifiable {
    let id = UUID()
    let period: BudgetPeriod
    let envelope: Envelope?
}
