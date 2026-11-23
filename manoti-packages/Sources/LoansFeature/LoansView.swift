//
//  LoansView.swift
//  LoansFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// The loans list, pushed from Home without its own navigation stack.
public struct LoansView: View {
    @Environment(LoanService.self) private var loanService

    @State private var loans: [Loan] = []
    @State private var formDirection: LoanDirection?

    public init() {}

    public var body: some View {
        Group {
            if loans.isEmpty {
                emptyState
            } else {
                loanList
            }
        }
        .navigationTitle("Loans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Lend money", systemImage: LoanDirection.lent.symbolName) {
                        formDirection = .lent
                    }

                    Button("Borrow money", systemImage: LoanDirection.borrowed.symbolName) {
                        formDirection = .borrowed
                    }
                } label: {
                    Label("Add loan", systemImage: "plus")
                }
            }
        }
        .sheet(item: $formDirection) { direction in
            LoanFormView(direction: direction)
        }
        .onManotiDataChange { reload() }
    }

    private var loanList: some View {
        List {
            section(title: "Owed to me", loans: loans.filter { $0.direction == .lent })
            section(title: "I owe", loans: loans.filter { $0.direction == .borrowed })
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
    }

    @ViewBuilder
    private func section(title: String, loans: [Loan]) -> some View {
        if !loans.isEmpty {
            Section(title) {
                ForEach(loans) { loan in
                    NavigationLink {
                        LoanDetailView(loan: loan)
                    } label: {
                        LoanRowView(loan: loan)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: ManotiSpacing.large) {
                EmptyStateView(
                    symbolName: "arrow.left.arrow.right.circle",
                    title: "No loans yet",
                    message:
                        "Track money you lend to friends and family, or money you borrow, without counting it as spending."
                )

                VStack(spacing: ManotiSpacing.small) {
                    Button {
                        formDirection = .lent
                    } label: {
                        Label("Lend money", systemImage: LoanDirection.lent.symbolName)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        formDirection = .borrowed
                    } label: {
                        Label("Borrow money", systemImage: LoanDirection.borrowed.symbolName)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, ManotiSpacing.regular)
            }
            .padding(.bottom, 88)
            .padding(.horizontal, ManotiSpacing.regular)
            .padding(.top, ManotiSpacing.extraLarge)
        }
    }

    private func reload() {
        loans = (try? loanService.fetchLoans()) ?? []
    }
}
