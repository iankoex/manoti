//
//  RulesView.swift
//  RulesFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import SwiftData
import SwiftUI

public struct RulesView: View {
    @Environment(ParserService.self) private var parserService
    @Environment(RuleService.self) private var ruleService

    @State private var ruleSets: [ParseRuleSet] = []
    @State private var checks: [String] = []
    @State private var isTesting = false
    @State private var isShowingSetup = false
    @State private var isCreatingRule = false

    public init() {}

    public var body: some View {
        List {
            ForEach(ruleSets) { ruleSet in
                Section {
                    ForEach(ruleSet.orderedRules) { rule in
                        NavigationLink {
                            RuleEditorView(rule: rule, ruleSets: ruleSets)
                        } label: {
                            RuleRow(rule: rule)
                        }
                    }
                } header: {
                    Text(ruleSet.name)
                } footer: {
                    Text(ruleSet.notes)
                }
            }

            if !checks.isEmpty {
                Section("Checks") {
                    ForEach(checks, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Message rules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingRule = true
                } label: {
                    Label("New rule", systemImage: "plus")
                }
                .disabled(ruleSets.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Test a message", systemImage: "text.bubble") {
                        isTesting = true
                    }
                    Button("Shortcuts setup", systemImage: "bolt.badge.automatic") {
                        isShowingSetup = true
                    }
                } label: {
                    Label("Rule actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isTesting) {
            RulePlaygroundView()
        }
        .sheet(isPresented: $isShowingSetup) {
            ShortcutsSetupView()
        }
        .navigationDestination(isPresented: $isCreatingRule) {
            RuleEditorView(rule: nil, ruleSets: ruleSets)
        }
        .onManotiDataChange { reload() }
    }

    private func reload() {
        ruleSets = (try? parserService.ruleSets()) ?? []
        checks = (try? ruleService.collisionWarnings()) ?? []
    }
}

private struct RuleRow: View {
    let rule: ParseRule

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                Text(rule.messageType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !rule.isEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
