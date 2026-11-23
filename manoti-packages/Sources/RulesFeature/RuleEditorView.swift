//
//  RuleEditorView.swift
//  RulesFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import SwiftData
import SwiftUI

struct RuleEditorView: View {
    @Bindable var rule: ParseRule

    @Environment(\.dismiss) private var dismiss
    @Environment(RuleService.self) private var ruleService

    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Name", text: $rule.name)

                Picker("Records as", selection: $rule.messageTypeRaw) {
                    ForEach(LedgerEntryKind.allCases) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }

                Toggle("Enabled", isOn: $rule.isEnabled)
            }

            Section("Pattern") {
                TextEditor(text: $rule.pattern)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 140)
                    .plainTextInput()

                Text("Named groups: amount, payee, date, time, ampm, ref, counterpart, account, cardLast4.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(rule.name)
        .navigationBarTitleDisplayModeInlineCompat()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        guard ruleService.isValid(pattern: rule.pattern) else {
            errorMessage = "This pattern is not a valid regular expression."
            return
        }

        do {
            try ruleService.save()
            dismiss()
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
