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

    @State private var ruleSets: [ParseRuleSet] = []
    @State private var isTesting = false
    @State private var isShowingSetup = false

    public init() {}

    public var body: some View {
        List {
            ForEach(ruleSets) { ruleSet in
                Section {
                    ForEach(ruleSet.orderedRules) { rule in
                        NavigationLink {
                            RuleEditorView(rule: rule)
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
        }
        .navigationTitle("Message rules")
        .toolbar {
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
        .onManotiDataChange { reload() }
    }

    private func reload() {
        ruleSets = (try? parserService.ruleSets()) ?? []
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
