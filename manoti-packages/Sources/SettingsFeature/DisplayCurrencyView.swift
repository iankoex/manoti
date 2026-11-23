//
//  DisplayCurrencyView.swift
//  SettingsFeature
//

import AppModels
import AppServices
import SwiftUI

struct DisplayCurrencyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppService.self) private var appService

    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(CurrencyCatalog.supported) { currency in
                    Button {
                        select(currency)
                    } label: {
                        row(for: currency)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(
                    "Only supported currencies are listed. Decimal places are fixed per currency, so changing this setting never rescales stored amounts."
                )
            }
        }
        .navigationTitle("Display currency")
        .alert(
            "Could not change currency",
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

    private func row(for currency: Currency) -> some View {
        let isSelected = currency.code == appService.displayCurrency.code

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currency.code)
                    .font(.body.weight(isSelected ? .semibold : .regular))

                Text(currency.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ currency: Currency) {
        do {
            try appService.setDisplayCurrency(currency.code)
            dismiss()
        } catch {
            errorMessage = "That currency could not be selected."
        }
    }
}
