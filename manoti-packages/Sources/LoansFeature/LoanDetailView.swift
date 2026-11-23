//
//  LoanDetailView.swift
//  LoansFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Loan summary, timeline and actions. Pushed inside an existing navigation stack.
public struct LoanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LoanService.self) private var loanService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    private let loan: Loan

    @State private var entries: [LedgerEntry] = []
    @State private var isAddingRepayment = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    public init(loan: Loan) {
        self.loan = loan
    }

    public var body: some View {
        List {
            Section {
                header
            }

            Section("Details") {
                LabeledContent("Started", value: loan.startedAt.formatted(date: .abbreviated, time: .omitted))

                if let dueAt = loan.dueAt {
                    LabeledContent("Due", value: dueAt.formatted(date: .abbreviated, time: .omitted))
                }

                if !loan.note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(loan.note)
                    }
                }
            }

            Section("Timeline") {
                if entries.isEmpty {
                    Text("No entries yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        TimelineRow(entry: entry, counterparty: loan.counterparty)
                    }
                }
            }

            Section {
                Button("Add repayment", systemImage: "arrow.down.left.circle") {
                    isAddingRepayment = true
                }
                .disabled(loan.status == .settled || loan.outstandingMinor <= 0)
            } footer: {
                if loan.status == .settled {
                    Text("This loan is fully repaid.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Delete loan", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            } footer: {
                Text("Deleting reverses the account balance and removes the loan from lists.")
            }
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle(loan.counterparty)
        .sheet(isPresented: $isAddingRepayment) {
            RepaymentFormView(loan: loan)
        }
        .alert("Delete this loan?", isPresented: $isConfirmingDelete) {
            Button("Delete loan", role: .destructive, action: deleteLoan)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The cash movements for \(loan.counterparty) will be reversed and the loan hidden.")
        }
        .alert(
            "Could not complete",
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

    private var header: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack {
                Label(directionTitle, systemImage: loan.direction.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)

                Spacer()

                if loan.status == .settled {
                    Text("Settled")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: .capsule)
                } else if isOverdue {
                    Text("Overdue")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red, in: .capsule)
                }
            }

            AmountText(loan.outstanding, style: .system(size: 36, weight: .semibold, design: .rounded))

            Text("Original \(AmountMask.money(principal, hidden: amountsHidden))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var principal: Money {
        Money(minorUnits: loan.principalMinor, currency: loan.currency)
    }

    private var directionTitle: String {
        switch loan.direction {
            case .lent: "Owed to me"
            case .borrowed: "I owe"
        }
    }

    private var tint: Color {
        switch loan.direction {
            case .lent: ManotiColor.forHex("#27AE60")
            case .borrowed: ManotiColor.forHex("#EB5757")
        }
    }

    private var isOverdue: Bool {
        guard loan.status == .open, loan.outstandingMinor > 0, let dueAt = loan.dueAt else {
            return false
        }

        let calendar = Calendar.current
        return calendar.startOfDay(for: dueAt) < calendar.startOfDay(for: Date.now)
    }

    private func reload() {
        entries = (loan.entries ?? [])
            .filter { !$0.isSoftDeleted }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    private func deleteLoan() {
        do {
            try loanService.delete(loan)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TimelineRow: View {
    let entry: LedgerEntry
    let counterparty: String

    var body: some View {
        HStack(spacing: ManotiSpacing.medium) {
            Image(systemName: entry.kind.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.4), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(entry.occurredAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: ManotiSpacing.small)

            AmountText(
                Money(minorUnits: entry.signedAmountMinor, currency: entry.currency),
                showsSign: true,
                style: .subheadline.weight(.medium)
            )
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch entry.kind {
            case .loanOut: "Loan to \(counterparty)"
            case .loanIn: "Loan from \(counterparty)"
            case .loanRepaymentIn: "Repayment from \(counterparty)"
            case .loanRepaymentOut: "Repayment to \(counterparty)"
            default: entry.kind.displayName
        }
    }
}
