//
//  AccountEditorView.swift
//  AccountsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var accountService

    private let account: Account?

    @State private var name: String
    @State private var kind: AccountKind
    @State private var ownership: AccountOwnership
    @State private var currencyCode: String
    @State private var colorHex: String
    @State private var symbolName: String
    @State private var institution: String
    @State private var openingText = ""
    @State private var errorMessage: String?

    init(account: Account?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _kind = State(initialValue: account?.kind ?? .bank)
        _ownership = State(initialValue: account?.ownership ?? .personal)
        _currencyCode = State(initialValue: account?.currencyCode ?? CurrencyCatalog.defaultCurrency.code)
        _colorHex = State(initialValue: account?.colorHex ?? ManotiPalette.accountColours[0])
        _symbolName = State(initialValue: account?.symbolName ?? ManotiPalette.accountSymbols[0])
        _institution = State(initialValue: account?.institution ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                appearanceSection
                if account == nil {
                    openingSection
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(account == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Account") {
            TextField("Name", text: $name)

            Picker("Type", selection: $kind) {
                ForEach(AccountKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            Picker("Owner", selection: $ownership) {
                ForEach(AccountOwnership.allCases) { ownership in
                    Text(ownership.displayName).tag(ownership)
                }
            }

            Picker("Currency", selection: $currencyCode) {
                ForEach(CurrencyCatalog.supported) { currency in
                    Text(currency.code).tag(currency.code)
                }
            }
            .disabled(account != nil)

            TextField("Bank or provider (optional)", text: $institution)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(ManotiPalette.accountColours, id: \.self) { hex in
                    ColourSwatch(hex: hex, isSelected: colorHex == hex)
                        .onTapGesture { colorHex = hex }
                }
            }
            .padding(.vertical, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(ManotiPalette.accountSymbols, id: \.self) { symbol in
                    SymbolSwatch(symbol: symbol, hex: colorHex, isSelected: symbolName == symbol)
                        .onTapGesture { symbolName = symbol }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var openingSection: some View {
        Section("Opening balance") {
            TextField("0.00", text: $openingText)
                .decimalKeyboard()
                .monospacedDigit()
        }
    }

    private func save() {
        do {
            if let account {
                try accountService.updateDetails(
                    account,
                    name: name,
                    kind: kind,
                    colorHex: colorHex,
                    symbolName: symbolName,
                    institution: institution,
                    ownership: ownership
                )
            } else {
                let currency = CurrencyCatalog.currency(for: currencyCode)
                let opening =
                    MoneyParser.parse(
                        openingText.isEmpty ? "0" : openingText,
                        defaultCurrency: currency
                    )?.money.minorUnits ?? 0

                try accountService.create(
                    name: name,
                    kind: kind,
                    currencyCode: currencyCode,
                    colorHex: colorHex,
                    symbolName: symbolName,
                    ownership: ownership,
                    openingBalanceMinor: opening
                )
            }

            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
            case AccountError.emptyName:
                "Give the account a name."
            case AccountError.duplicateName:
                "An account with that name already exists."
            case LedgerError.nonPositiveAmount, MoneyError.invalidAmount:
                "Enter a valid opening balance."
            default:
                error.localizedDescription
        }
    }
}

private struct ColourSwatch: View {
    let hex: String
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(ManotiColor.forHex(hex))
            .frame(width: 28, height: 28)
            .overlay {
                Circle()
                    .strokeBorder(.primary, lineWidth: isSelected ? 2 : 0)
                    .padding(-3)
            }
            .accessibilityLabel(hex)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SymbolSwatch: View {
    let symbol: String
    let hex: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(ManotiColor.forHex(hex))
            .frame(width: 34, height: 34)
            .background(
                ManotiColor.forHex(hex).opacity(isSelected ? 0.22 : 0.08),
                in: .rect(cornerRadius: 8)
            )
            .accessibilityLabel(symbol)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
