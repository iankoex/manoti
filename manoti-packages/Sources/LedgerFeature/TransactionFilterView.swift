//
//  TransactionFilterView.swift
//  LedgerFeature
//

import AppModels
import Modifiers
import SwiftUI

struct TransactionFilterView: View {
    @Binding var filter: TransactionFilter
    let currency: Currency
    let accounts: [Account]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AccountKind.allCases) { kind in
                        Toggle(kind.displayName, isOn: kindBinding(kind))
                    }
                } header: {
                    Text("Account type")
                } footer: {
                    Text("All types are on. Turn one off to leave it out.")
                }

                Section {
                    if accounts.isEmpty {
                        Text("No accounts yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(accounts) { account in
                            Toggle(isOn: accountBinding(account)) {
                                HStack(spacing: 10) {
                                    Image(systemName: account.symbolName)
                                        .font(.caption)
                                        .foregroundStyle(ManotiColor.forHex(account.colorHex))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            ManotiColor.forHex(account.colorHex).opacity(0.14),
                                            in: .circle
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.displayName)

                                        Text(subtitle(for: account))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(!filter.accountKinds.contains(account.kind))
                        }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("All accounts are on. Turn one off to leave it out; turning its type off disables it.")
                }

                Section("Amount in \(currency.code)") {
                    TextField("No minimum", text: $filter.minimumAmountText)
                        .decimalKeyboard()
                    TextField("No maximum", text: $filter.maximumAmountText)
                        .decimalKeyboard()
                }

                Section("Date") {
                    Picker("Range", selection: $filter.datePreset) {
                        ForEach(TransactionDatePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }

                    if filter.datePreset == .custom {
                        Picker("Match", selection: $filter.dateMode) {
                            ForEach(TransactionDateMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if filter.dateMode == .between {
                            DatePicker("From", selection: $filter.customFrom, displayedComponents: .date)
                            DatePicker("To", selection: $filter.customTo, displayedComponents: .date)
                        } else {
                            DatePicker(
                                filter.dateMode == .before ? "Before" : "After",
                                selection: $filter.customFrom,
                                displayedComponents: .date
                            )
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filter.reset()
                    }
                    .disabled(!filter.isActive)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func kindBinding(_ kind: AccountKind) -> Binding<Bool> {
        Binding(
            get: { filter.accountKinds.contains(kind) },
            set: { isOn in
                if isOn {
                    filter.accountKinds.insert(kind)
                    if !accounts.isEmpty {
                        var ids = filter.accountIDs.isEmpty ? allAccountIDs : filter.accountIDs
                        ids.formUnion(accounts.filter { $0.kind == kind }.map(\.id))
                        filter.accountIDs = ids == allAccountIDs ? [] : ids
                    }
                } else {
                    filter.accountKinds.remove(kind)
                    if !accounts.isEmpty {
                        // A disabled type must not stay selected underneath.
                        var ids = filter.accountIDs.isEmpty ? allAccountIDs : filter.accountIDs
                        ids.subtract(Set(accounts.filter { $0.kind == kind }.map(\.id)))
                        filter.accountIDs = ids == allAccountIDs ? [] : ids
                    }
                }
            }
        )
    }

    private var allAccountIDs: Set<UUID> {
        Set(accounts.map(\.id))
    }

    private func isAccountOn(_ account: Account) -> Bool {
        filter.accountIDs.isEmpty || filter.accountIDs.contains(account.id)
    }

    private func accountBinding(_ account: Account) -> Binding<Bool> {
        Binding(
            get: { isAccountOn(account) },
            set: { isOn in
                var ids = filter.accountIDs.isEmpty ? allAccountIDs : filter.accountIDs

                if isOn {
                    ids.insert(account.id)
                } else {
                    ids.remove(account.id)
                }

                // Back to "all" when every account is on, so the filter stays inactive.
                filter.accountIDs = ids == allAccountIDs ? [] : ids
            }
        )
    }

    private func subtitle(for account: Account) -> String {
        let base = "\(account.kind.displayName) · \(account.currency.code)"
        return account.isArchived ? "\(base) · Archived" : base
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
