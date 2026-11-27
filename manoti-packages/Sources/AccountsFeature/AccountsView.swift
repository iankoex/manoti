//
//  AccountsView.swift
//  AccountsFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import SwiftUI

public struct AccountsView: View {
    @Environment(AccountService.self) private var accountService

    @State private var accounts: [Account] = []
    @State private var editorTarget: AccountEditorTarget?

    private let embedded: Bool

    /// Creates the accounts screen.
    /// - Parameter embedded: When `true`, renders the list without its own `NavigationStack` or navigation
    ///   title so it can be pushed inside an existing navigation stack. Defaults to `false`.
    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    public var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Accounts")
            }
        }
    }

    private var content: some View {
        Group {
            if accounts.isEmpty {
                EmptyStateView(
                    symbolName: "wallet.bifold",
                    title: "No accounts yet",
                    message: "Add your bank, mobile money or cash accounts to start tracking."
                )
            } else {
                accountList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add account", systemImage: "plus") {
                    editorTarget = .create
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            AccountEditorView(account: target.account)
        }
        .onManotiDataChange { reload() }
    }

    private var accountList: some View {
        List {
            if companyAccounts.isEmpty {
                Section {
                    ForEach(activeAccounts) { account in
                        accountRow(account)
                    }
                }
            } else {
                Section("Personal") {
                    ForEach(personalAccounts) { account in
                        accountRow(account)
                    }
                }

                Section("Company") {
                    ForEach(companyAccounts) { account in
                        accountRow(account)
                    }
                }
            }

            if !archivedAccounts.isEmpty {
                Section("Archived") {
                    ForEach(archivedAccounts) { account in
                        AccountRowView(account: account)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        NavigationLink {
            AccountDetailView(account: account)
        } label: {
            AccountRowView(account: account)
        }
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var personalAccounts: [Account] {
        activeAccounts.filter { !$0.isCompany }
    }

    private var companyAccounts: [Account] {
        activeAccounts.filter(\.isCompany)
    }

    private var archivedAccounts: [Account] {
        accounts.filter(\.isArchived)
    }

    private func reload() {
        accounts = (try? accountService.fetchAccounts(includeArchived: true)) ?? []
    }
}

enum AccountEditorTarget: Identifiable {
    case create
    case edit(Account)

    var id: String {
        switch self {
            case .create: "create"
            case .edit(let account): account.id.uuidString
        }
    }

    var account: Account? {
        switch self {
            case .create: nil
            case .edit(let account): account
        }
    }
}
