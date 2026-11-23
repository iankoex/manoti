//
//  RulePlaygroundView.swift
//  RulesFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftData
import SwiftUI

struct RulePlaygroundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ParserService.self) private var parserService
    @Environment(IngestService.self) private var ingestService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var sender = "M-PESA"
    @State private var message = ""
    @State private var parsed: ParsedMessage?
    @State private var status: String?
    @State private var queuedSummary: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    TextField("Sender", text: $sender)
                        .plainTextInput()

                    TextEditor(text: $message)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 160)
                        .plainTextInput()
                }

                Section {
                    Button("Test message", action: test)
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(action: ingest) {
                        Text("Send to Inbox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let parsed {
                    Section("Captured") {
                        LabeledContent("Rule", value: "\(parsed.ruleSetName) · \(parsed.ruleName)")
                        LabeledContent("Type", value: parsed.messageType.displayName)
                        LabeledContent(
                            "Amount",
                            value: AmountMask.money(
                                Money(
                                    minorUnits: parsed.amountMinor,
                                    currency: CurrencyCatalog.currency(for: parsed.currencyCode)
                                ),
                                hidden: amountsHidden
                            )
                        )

                        if parsed.feeMinor != 0 {
                            LabeledContent(
                                "Fee",
                                value: AmountMask.money(
                                    Money(
                                        minorUnits: parsed.feeMinor,
                                        currency: CurrencyCatalog.currency(for: parsed.currencyCode)
                                    ),
                                    hidden: amountsHidden
                                )
                            )
                        }

                        if !parsed.payee.isEmpty {
                            LabeledContent("Payee", value: parsed.payee)
                        }

                        if !parsed.reference.isEmpty {
                            LabeledContent("Reference", value: parsed.reference)
                        }

                        if !parsed.counterpartReference.isEmpty {
                            LabeledContent("Counterpart", value: parsed.counterpartReference)
                        }

                        LabeledContent(
                            "Date from message", value: parsed.dateFromMessage ? "Yes" : "No (used received time)")
                        LabeledContent("Confidence", value: "\(Int(parsed.confidence * 100))%")
                    }
                }

                if let status {
                    Section("Result") {
                        Text(AmountMask.text(status, hidden: amountsHidden))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Test a message")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .alert(
                "Sent to Inbox",
                isPresented: Binding(
                    get: { queuedSummary != nil },
                    set: { if !$0 { queuedSummary = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(AmountMask.text(queuedSummary ?? "", hidden: amountsHidden))
            }
            .onChange(of: message) { _, _ in
                parsed = nil
                status = nil
                errorMessage = nil
            }
        }
    }

    private func test() {
        do {
            switch try parserService.parse(text: message, sender: sender) {
                case .parsed(let message):
                    parsed = message
                    errorMessage = nil
                case .unrecognised:
                    parsed = nil
                    errorMessage = "No rule matched this message."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ingest() {
        do {
            let outcome = try ingestService.ingest(text: message, sender: sender)
            status = outcome.summary
            queuedSummary = outcome.summary
            test()
        } catch {
            errorMessage = error.localizedDescription
        }
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
