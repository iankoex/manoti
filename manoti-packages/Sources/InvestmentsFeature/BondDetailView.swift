//
//  BondDetailView.swift
//  InvestmentsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Bond terms, the verified coupon schedule and illustrative projections.
public struct BondDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppService.self) private var appService
    @Environment(InvestmentService.self) private var investmentService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    let investment: Investment

    @State private var isAddingCoupon = false
    @State private var isEditingNote = false
    @State private var isConfirmingDelete = false
    @State private var mismatches: [ScheduleMismatch]?
    @State private var errorMessage: String?
    @State private var actionError: String?

    public init(investment: Investment) {
        self.investment = investment
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                header
                termsCard

                if investment.type == .treasuryBond && investment.status != .matured {
                    verifiedCard
                    ReinvestmentProjectionView(investment: investment)
                } else {
                    valueCard
                }

                if !investment.note.isEmpty {
                    Text(investment.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ManotiSpacing.regular)
                        .background(.quaternary.opacity(0.2), in: .rect(cornerRadius: 16))
                }

                managementCard
            }
            .padding(.horizontal, ManotiSpacing.regular)
            .padding(.bottom, 88)
        }
        .background(.background)
        .navigationTitle(investment.issueNumber.isEmpty ? investment.type.displayName : investment.issueNumber)
        .toolbar {
            if investment.type == .treasuryBond && investment.status != .matured {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add coupon", systemImage: "plus") {
                        isAddingCoupon = true
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingCoupon) {
            AddCouponSheet(investment: investment)
        }
        .sheet(isPresented: $isEditingNote) {
            EditNoteSheet(investment: investment)
        }
        .confirmationDialog(
            "Delete this investment?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete investment", role: .destructive, action: deleteInvestment)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This reverses the linked cash movements and hides the holding from lists and net worth. The rows stay recoverable."
            )
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
        .alert(
            "Could not update investment",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var managementCard: some View {
        VStack(spacing: 0) {
            Button {
                isEditingNote = true
            } label: {
                Label("Edit note", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ManotiSpacing.regular)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if investment.status == .active {
                Divider()

                Button(action: redeemFaceValue) {
                    Label("Redeem face value", systemImage: "arrow.down.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ManotiSpacing.regular)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(investment.remainingFaceMinor <= 0)
            }

            Divider()

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete investment", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ManotiSpacing.regular)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .background(.quaternary.opacity(0.2), in: .rect(cornerRadius: 16))
    }

    private func redeemFaceValue() {
        do {
            try investmentService.redeem(
                investment,
                date: Date(),
                amountMinor: investment.remainingFaceMinor
            )
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Label(investment.type.displayName, systemImage: investment.type.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer()

                Text(investment.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(investment.isPending ? .orange : .secondary)
                    .padding(.horizontal, ManotiSpacing.small)
                    .padding(.vertical, 3)
                    .background(
                        investment.isPending ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.12),
                        in: .capsule
                    )
            }

            AmountText(investment.nominal, style: .system(size: 34, weight: .semibold, design: .rounded))

            Text("nominal")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let nextCoupon {
                HStack(spacing: ManotiSpacing.small) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next coupon \(nextCoupon.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline.weight(.medium))

                        Text(
                            "Gross \(AmountMask.money(nextCoupon.gross(in: investment.currency), hidden: amountsHidden)) · tax \(AmountMask.money(nextCoupon.tax(in: investment.currency), hidden: amountsHidden)) · net \(AmountMask.money(nextCoupon.net(in: investment.currency), hidden: amountsHidden))"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, ManotiSpacing.tiny)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            Text("Terms")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TermRow(title: "Issue", value: investment.issueNumber.isEmpty ? "—" : investment.issueNumber)

            if !investment.isin.isEmpty {
                TermRow(title: "ISIN", value: investment.isin)
            }

            TermRow(title: "Nominal", value: AmountMask.money(investment.nominal, hidden: amountsHidden))
            TermRow(title: "Cash invested", value: AmountMask.money(investment.cashInvested, hidden: amountsHidden))

            switch investment.type {
                case .treasuryBond:
                    TermRow(title: "Coupon", value: "\(percent(investment.couponRateBasisPoints))%")
                    TermRow(
                        title: "Withholding tax",
                        value: investment.taxExempt ? "Exempt" : "\(investment.withholdingTaxBasisPoints / 100)%"
                    )

                    if let issueDate = investment.issueDate {
                        TermRow(title: "Issued", value: issueDate.formatted(date: .abbreviated, time: .omitted))
                    }

                    TermRow(
                        title: "Purchased", value: investment.purchaseDate.formatted(date: .abbreviated, time: .omitted)
                    )

                    if let settlementDate = investment.settlementDate {
                        TermRow(
                            title: "Settles",
                            value: settlementDate.formatted(date: .abbreviated, time: .omitted)
                        )
                    }

                    if let maturityDate = investment.maturityDate {
                        TermRow(
                            title: "Matures",
                            value: maturityDate.formatted(date: .abbreviated, time: .omitted)
                        )
                    }

                    if let cleanPrice = investment.cleanPricePer100Scaled {
                        TermRow(
                            title: "Clean price",
                            value: "\(InvestmentMath.pricePer100(fromScaled: cleanPrice)) per 100"
                        )
                    }

                    TermRow(title: "Accrued interest", value: AmountMask.money(accrued, hidden: amountsHidden))
                    TermRow(
                        title: "Reinvestment rate",
                        value:
                            "\(Decimal(investment.reinvestmentRateBasisPoints ?? appService.reinvestmentRateBasisPoints) / 100)% gross"
                    )

                case .treasuryBill:
                    if let maturityDate = investment.maturityDate {
                        TermRow(
                            title: "Matures",
                            value: maturityDate.formatted(date: .abbreviated, time: .omitted)
                        )
                    }

                case .moneyMarket:
                    TermRow(title: "Annual rate", value: "\(percent(investment.annualRateBasisPoints))%")
                    TermRow(title: "Compounding", value: investment.compounding.displayName)

                    if let startDate = investment.startDate {
                        TermRow(title: "Started", value: startDate.formatted(date: .abbreviated, time: .omitted))
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var verifiedCard: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Label {
                    Text("Verified cash flow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(ManotiColor.forHex("#27AE60"))
                }

                Spacer()

                Text("Not a projection")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Remaining net coupons") {
                AmountText(remainingNetCoupons, style: .headline.weight(.semibold))
            }

            LabeledContent("Coupons left") {
                Text("\(remainingCoupons.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: ManotiSpacing.small) {
                NavigationLink {
                    CouponScheduleView(investment: investment)
                } label: {
                    Label("Schedule", systemImage: "tablecells")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    verify()
                } label: {
                    Label("Verify", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let mismatches {
                if mismatches.isEmpty {
                    Label("All recorded coupons match the schedule.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label(
                        "\(mismatches.count) schedule \(mismatches.count == 1 ? "difference" : "differences") found.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            Text("Value")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LabeledContent("Today") {
                AmountText(investment.currentValue, style: .headline.weight(.semibold))
            }

            if investment.type == .treasuryBill, let maturityDate = investment.maturityDate {
                LabeledContent("At maturity") {
                    Text(
                        "\(maturityDate.formatted(date: .abbreviated, time: .omitted)) · \(AmountMask.money(investment.nominal, hidden: amountsHidden))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            if investment.type == .moneyMarket {
                Text("Daily compounding at the after-tax annual rate. Not a bank statement balance.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private var remainingCoupons: [CouponScheduleEntry] {
        guard investment.type == .treasuryBond else {
            return []
        }

        return InvestmentMath.couponSchedule(for: investment, from: Date.now)
    }

    private var nextCoupon: CouponScheduleEntry? {
        remainingCoupons.first
    }

    private var remainingNetCoupons: Money {
        Money(
            minorUnits: remainingCoupons.reduce(into: Int64(0)) { total, entry in total += entry.netMinor },
            currency: investment.currency
        )
    }

    private var accrued: Money {
        Money(minorUnits: investment.accruedInterestMinor, currency: investment.currency)
    }

    private var tint: Color {
        switch investment.type {
            case .treasuryBond: ManotiColor.forHex("#27AE60")
            case .treasuryBill: ManotiColor.forHex("#2F80ED")
            case .moneyMarket: ManotiColor.forHex("#9B51E0")
        }
    }

    private func percent(_ basisPoints: Decimal) -> String {
        "\(basisPoints / 100)"
    }

    private func verify() {
        mismatches = investmentService.verifySchedule(investment)
    }

    private func deleteInvestment() {
        do {
            try investmentService.delete(investment)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct EditNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(InvestmentService.self) private var investmentService

    let investment: Investment

    @State private var note: String
    @State private var errorMessage: String?

    init(investment: Investment) {
        self.investment = investment
        _note = State(initialValue: investment.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                }
            }
            .alert(
                "Could not save note",
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

    private func save() {
        do {
            try investmentService.updateNote(investment, note: note)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TermRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
