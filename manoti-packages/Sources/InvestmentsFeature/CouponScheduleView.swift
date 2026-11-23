//
//  CouponScheduleView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// The expected coupon table, recorded payments and schedule verification.
public struct CouponScheduleView: View {
    @Environment(InvestmentService.self) private var investmentService

    let investment: Investment

    @State private var isAddingCoupon = false
    @State private var mismatches: [ScheduleMismatch]?
    @State private var errorMessage: String?

    public init(investment: Investment) {
        self.investment = investment
    }

    public var body: some View {
        List {
            Section {
                if rows.isEmpty {
                    Text("No coupon schedule yet. Add the first coupon date on the bond.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        CouponRow(row: row, currency: investment.currency)
                    }
                }
            } header: {
                Text("Expected schedule")
            } footer: {
                Text(
                    "Dates and amounts come from the bond's recorded terms. A paid row is matched by calendar day."
                )
            }

            if !paidFlows.isEmpty {
                Section("Recorded payments") {
                    ForEach(paidFlows) { flow in
                        LabeledContent(flow.date.formatted(date: .abbreviated, time: .omitted)) {
                            AmountText(flow.net, style: .subheadline.weight(.semibold))
                        }
                    }
                }
            }

            Section("Verification") {
                Button {
                    verify()
                } label: {
                    Label("Verify schedule", systemImage: "checkmark.seal")
                }

                if let mismatches {
                    if mismatches.isEmpty {
                        Label("Every recorded coupon matches the schedule.", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        ForEach(mismatches) { mismatch in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mismatch.message)
                                    .font(.subheadline)

                                if let date = mismatch.expectedDate ?? mismatch.actualDate {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Coupon schedule")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add coupon", systemImage: "plus") {
                    isAddingCoupon = true
                }
            }
        }
        .sheet(isPresented: $isAddingCoupon) {
            AddCouponSheet(investment: investment)
        }
        .alert(
            "Could not verify",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var rows: [CouponScheduleRow] {
        let schedule = InvestmentMath.couponSchedule(for: investment, from: investment.purchaseDate)
        let paid = paidFlows

        return schedule.map { entry in
            let matching = paid.first {
                InvestmentMath.calendar.isDate($0.date, inSameDayAs: entry.date)
            }
            return CouponScheduleRow(entry: entry, paid: matching)
        }
    }

    private var paidFlows: [InvestmentCashFlow] {
        (investment.cashFlows ?? [])
            .filter { $0.kind == .coupon && $0.status == .paid && !$0.isSoftDeleted }
            .sorted { $0.date < $1.date }
    }

    private func verify() {
        guard investment.type == .treasuryBond else {
            errorMessage = "Coupon schedules apply to Treasury bonds only."
            return
        }

        mismatches = investmentService.verifySchedule(investment)
    }
}

private struct CouponScheduleRow: Identifiable {
    let entry: CouponScheduleEntry
    let paid: InvestmentCashFlow?

    var id: Date { entry.date }

    var isPaid: Bool { paid != nil }
}

private struct CouponRow: View {
    let row: CouponScheduleRow
    let currency: Currency

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(row.isPaid ? "Paid" : "Scheduled")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isPaid ? Color.green : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        row.isPaid ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12),
                        in: .capsule
                    )
            }

            HStack(spacing: ManotiSpacing.medium) {
                Text("Gross \(AmountMask.money(row.entry.gross(in: currency), hidden: amountsHidden))")
                Text("Tax \(AmountMask.money(row.entry.tax(in: currency), hidden: amountsHidden))")
                Spacer()
                Text("Net \(AmountMask.money(row.entry.net(in: currency), hidden: amountsHidden))")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(row.entry.date.formatted(date: .abbreviated, time: .omitted)), net \(AmountMask.money(row.entry.net(in: currency), hidden: amountsHidden)), \(row.isPaid ? "paid" : "scheduled")"
        )
    }
}

struct AddCouponSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvestmentService.self) private var investmentService

    let investment: Investment

    @State private var date: Date
    @State private var grossText: String
    @State private var taxText: String
    @State private var note = ""
    @State private var errorMessage: String?

    init(investment: Investment) {
        self.investment = investment

        let next = InvestmentMath.couponSchedule(for: investment, from: Date.now).first
        let gross = next?.grossMinor ?? InvestmentMath.grossCouponMinor(for: investment)
        let tax = next?.taxMinor ?? InvestmentMath.taxMinor(for: investment)

        _date = State(initialValue: next?.date ?? Date.now)
        _grossText = State(initialValue: "\(Decimal(gross) / 100)")
        _taxText = State(initialValue: "\(Decimal(tax) / 100)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Paid on", selection: $date, displayedComponents: .date)
                }

                Section {
                    LabeledContent("Gross") {
                        HStack(spacing: ManotiSpacing.small) {
                            Text(currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("0.00", text: $grossText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Withholding tax") {
                        HStack(spacing: ManotiSpacing.small) {
                            Text(currency.code)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("0.00", text: $taxText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    }

                    if let net {
                        LabeledContent("Net") {
                            AmountText(net, style: .subheadline.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Coupon")
                } footer: {
                    if let message = validationMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Note")
                }
            }
            .navigationTitle("Record coupon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(validationMessage != nil)
                }
            }
            .alert(
                "Could not record coupon",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var currency: Currency {
        investment.currency
    }

    private var gross: Money? {
        MoneyParser.parse(grossText, defaultCurrency: currency)?.money
    }

    private var tax: Money? {
        MoneyParser.parse(taxText, defaultCurrency: currency)?.money
    }

    private var net: Money? {
        guard let gross, let tax, gross.minorUnits >= tax.minorUnits else {
            return nil
        }

        return Money(minorUnits: gross.minorUnits - tax.minorUnits, currency: gross.currency)
    }

    private var validationMessage: String? {
        guard let gross else {
            return "Enter a valid gross coupon."
        }

        guard let tax else {
            return "Enter a valid withholding tax."
        }

        if gross.minorUnits <= 0 {
            return "The gross coupon must be greater than zero."
        }

        if tax.minorUnits < 0 || tax.minorUnits > gross.minorUnits {
            return "Withholding tax cannot exceed the gross coupon."
        }

        return nil
    }

    private func save() {
        guard let gross, let tax else {
            errorMessage = "Check the coupon amounts."
            return
        }

        do {
            try investmentService.recordCoupon(
                investment,
                date: date,
                grossMinor: gross.minorUnits,
                taxMinor: tax.minorUnits,
                note: note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
