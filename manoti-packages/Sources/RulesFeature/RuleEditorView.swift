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
    private let rule: ParseRule?
    private let ruleSets: [ParseRuleSet]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RuleService.self) private var ruleService

    @State private var name: String
    @State private var messageTypeRaw: String
    @State private var isEnabled: Bool
    @State private var pattern: String
    @State private var ruleSetID: UUID?
    @State private var errorMessage: String?

    /// Pass a rule to edit it, or `nil` to create one in `ruleSets.first`.
    init(rule: ParseRule?, ruleSets: [ParseRuleSet]) {
        self.rule = rule
        self.ruleSets = ruleSets
        _name = State(initialValue: rule?.name ?? "")
        _messageTypeRaw = State(initialValue: rule?.messageTypeRaw ?? LedgerEntryKind.expense.rawValue)
        _isEnabled = State(initialValue: rule?.isEnabled ?? true)
        _pattern = State(initialValue: rule?.pattern ?? "")
        _ruleSetID = State(initialValue: rule?.ruleSet?.id ?? ruleSets.first?.id)
    }

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Name", text: $name)

                if rule == nil {
                    Picker("Rule set", selection: $ruleSetID) {
                        ForEach(ruleSets) { ruleSet in
                            Text(ruleSet.name).tag(Optional(ruleSet.id))
                        }
                    }
                }

                Picker("Records as", selection: $messageTypeRaw) {
                    ForEach(LedgerEntryKind.allCases) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }

                Toggle("Enabled", isOn: $isEnabled)
            }

            Section("Pattern") {
                TextEditor(text: $pattern)
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
        .navigationTitle(rule == nil ? "New rule" : name)
        .navigationBarTitleDisplayModeInlineCompat()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
    }

    private func save() {
        guard let ruleSet = ruleSets.first(where: { $0.id == ruleSetID }) else {
            errorMessage = "Choose a rule set."
            return
        }

        let message: String?
        do {
            message = try ruleService.validationMessage(
                name: name,
                pattern: pattern,
                fieldPatterns: rule?.fieldPatterns ?? [:],
                in: ruleSet,
                excluding: rule
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if let message {
            errorMessage = message
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let rule {
            rule.name = trimmedName
            rule.messageTypeRaw = messageTypeRaw
            rule.isEnabled = isEnabled
            rule.pattern = pattern
            rule.ruleSet = ruleSet
        } else {
            let newRule = ParseRule(
                name: trimmedName,
                messageType: LedgerEntryKind(rawValue: messageTypeRaw) ?? .expense,
                pattern: pattern,
                priority: (ruleSet.rules ?? []).count
            )
            newRule.isEnabled = isEnabled
            newRule.ruleSet = ruleSet
            context.insert(newRule)
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
