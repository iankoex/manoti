//
//  ExchangeRateEditorView.swift
//  SettingsFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import SwiftUI

struct ExchangeRateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppService.self) private var appService
    @Environment(ExchangeRateService.self) private var exchangeRates

    @State private var baseCode = "USD"
    @State private var quoteCode = "KES"
    @State private var rateText = ""
    @State private var asOf = Date()
    @State private var didSetDefaults = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Convert from", selection: $baseCode) {
                        ForEach(CurrencyCatalog.supported) { currency in
                            Text(currency.code).tag(currency.code)
                        }
                    }

                    Picker("To", selection: $quoteCode) {
                        ForEach(CurrencyCatalog.supported) { currency in
                            Text(currency.code).tag(currency.code)
                        }
                    }
                } footer: {
                    Text("1 \(baseCode) equals the rate you enter in \(quoteCode).")
                }

                Section("Rate") {
                    HStack(spacing: 8) {
                        TextField("0.00", text: $rateText)
                            .decimalKeyboard()
                            .font(.title3.weight(.medium).monospacedDigit())

                        Text(quoteCode)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker("As of", selection: $asOf, in: ...Date(), displayedComponents: .date)
                }

                if baseCode == quoteCode {
                    Section {
                        Label("Choose two different currencies.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else if let rate = parsedRate {
                    Section("Preview") {
                        LabeledContent("1 \(baseCode)", value: "\(formatted(rate)) \(quoteCode)")
                        LabeledContent("1 \(quoteCode)", value: "\(formatted(1 / rate)) \(baseCode)")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add rate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: setDefaults)
        }
    }

    private var baseCurrency: Currency {
        CurrencyCatalog.currency(for: baseCode)
    }

    private var quoteCurrency: Currency {
        CurrencyCatalog.currency(for: quoteCode)
    }

    private var parsedRate: Decimal? {
        var cleaned = rateText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        if cleaned.contains(",") {
            if cleaned.contains(".") {
                // `1,234.56`: the dot is the decimal separator.
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            } else {
                let trailing = cleaned.split(separator: ",").last?.count ?? 0
                cleaned =
                    trailing <= 2
                    ? cleaned.replacingOccurrences(of: ",", with: ".")
                    : cleaned.replacingOccurrences(of: ",", with: "")
            }
        }

        guard !cleaned.isEmpty,
            let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
            value > 0
        else {
            return nil
        }

        return value
    }

    private var canSave: Bool {
        baseCode != quoteCode && parsedRate != nil
    }

    private func setDefaults() {
        guard !didSetDefaults else {
            return
        }

        didSetDefaults = true
        quoteCode = appService.displayCurrency.code
        baseCode = quoteCode == "USD" ? "EUR" : "USD"
    }

    private func formatted(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2...6)))
    }

    private func save() {
        guard let rate = parsedRate, baseCode != quoteCode else {
            return
        }

        do {
            try exchangeRates.addRate(
                base: baseCurrency,
                quote: quoteCurrency,
                decimalRate: rate,
                asOf: Calendar.current.startOfDay(for: asOf)
            )
            dismiss()
        } catch {
            errorMessage = "That rate could not be saved. Check the currencies and try again."
        }
    }
}
