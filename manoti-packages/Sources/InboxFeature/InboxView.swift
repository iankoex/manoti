//
//  InboxView.swift
//  InboxFeature
//

import AppModels
import AppPackageExtensions
import AppServices
import Modifiers
import RulesFeature
import SettingsFeature
import SwiftUI

public struct InboxView: View {
    @Environment(InboxService.self) private var inboxService
    @Environment(PrivacyService.self) private var privacyService

    @State private var entries: [LedgerEntry] = []
    @State private var unparsed: [UnparsedMessage] = []
    @State private var autoIgnored: [LedgerEntry] = []
    @State private var selected: LedgerEntry?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty && unparsed.isEmpty && autoIgnored.isEmpty {
                    EmptyStateView(
                        symbolName: "tray",
                        title: "Inbox is clear",
                        message: "Bank and mobile money messages that need a category will wait here."
                    )
                } else {
                    List {
                        if !unparsed.isEmpty {
                            Section("Could not read") {
                                ForEach(unparsed) { message in
                                    UnparsedMessageRow(message: message)
                                        .swipeActions {
                                            Button("Dismiss", role: .destructive) {
                                                dismiss(message)
                                            }
                                        }
                                }
                            }
                        }

                        if !entries.isEmpty {
                            Section {
                                ForEach(entries) { entry in
                                    Button {
                                        selected = entry
                                    } label: {
                                        InboxRowView(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !autoIgnored.isEmpty {
                            Section {
                                DisclosureGroup("Auto-ignored (\(autoIgnored.count))") {
                                    ForEach(autoIgnored) { entry in
                                        HStack(spacing: 12) {
                                            InboxRowView(entry: entry)

                                            Button("Undo") {
                                                undo(entry)
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption.weight(.medium))
                                        }
                                    }
                                }
                            } footer: {
                                Text(
                                    "These match a message shape you ignored. Undo puts one back in Review and forgets the pattern."
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                SettingsToolbarItem()

                ToolbarItemGroup(placement: .primaryAction) {
                    PrivacyToolbarButton(isHidden: privacyService.isAmountsHidden) {
                        togglePrivacy()
                    }

                    NavigationLink {
                        RulesView()
                    } label: {
                        Label("Message rules", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .onManotiDataChange { reload() }
            .sheet(item: $selected) { entry in
                InboxDetailView(entry: entry)
            }
        }
    }

    private func reload() {
        entries = (try? inboxService.pending()) ?? []
        unparsed = (try? inboxService.unparsed()) ?? []
        autoIgnored = (try? inboxService.autoIgnored()) ?? []
        if selected?.isSoftDeleted == true {
            selected = nil
        }
    }

    private func undo(_ entry: LedgerEntry) {
        try? inboxService.undoAutoIgnore(entry)
    }

    private func dismiss(_ message: UnparsedMessage) {
        try? inboxService.dismiss(message)
    }

    private func togglePrivacy() {
        if privacyService.isAmountsHidden {
            privacyService.reveal()
        } else {
            privacyService.hide()
        }
    }
}

private struct UnparsedMessageRow: View {
    let message: UnparsedMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.rawText.isEmpty ? "Message text not kept" : message.rawText)
                .font(.caption)
                .lineLimit(3)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let when = message.receivedAt.formatted(date: .abbreviated, time: .shortened)
        return message.sender.isEmpty ? when : "\(message.sender) · \(when)"
    }
}

private struct InboxRowView: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.symbolName)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(.orange.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    AmountText(
                        Money(minorUnits: entry.amountMinor, currency: entry.currency),
                        style: .subheadline
                    )
                    .lineLimit(1)
                    .layoutPriority(1)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
    }

    private var title: String {
        entry.payee.isEmpty ? entry.kind.displayName : entry.payee
    }

    private var subtitle: String {
        let when = entry.occurredAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return entry.account == nil ? "\(when) · Needs account" : when
    }
}
