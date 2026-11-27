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
    @State private var isConfirmingClear = false
    @State private var isConfirmingClearUnparsed = false

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
                            Section {
                                DisclosureGroup(
                                    unparsed.count == 1 ? "1 message" : "\(unparsed.count) messages"
                                ) {
                                    ForEach(unparsed) { message in
                                        UnparsedMessageRow(message: message)
                                            .swipeActions {
                                                Button("Dismiss", role: .destructive) {
                                                    dismiss(message)
                                                }
                                            }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("Could not read")

                                    Spacer()

                                    Button("Clear all", role: .destructive) {
                                        isConfirmingClearUnparsed = true
                                    }
                                    .font(.caption.weight(.medium))
                                    .textCase(nil)
                                    .contentShape(.rect)
                                    .padding(.vertical, 6)
                                    .confirmationDialog(
                                        "Delete all unreadable messages?",
                                        isPresented: $isConfirmingClearUnparsed,
                                        titleVisibility: .visible
                                    ) {
                                        Button("Delete all messages", role: .destructive) {
                                            clearUnparsed()
                                        }

                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text(
                                            "This deletes the stored text of every message Manoti could not read, including ones dismissed earlier. Nothing is added to the ledger either way."
                                        )
                                    }
                                }
                            } footer: {
                                Text(
                                    "Manoti keeps these so a bank alert is never silently dropped."
                                )
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
                                DisclosureGroup(
                                    autoIgnored.count == 1 ? "1 message" : "\(autoIgnored.count) messages"
                                ) {
                                    ForEach(autoIgnored) { entry in
                                        InboxRowView(entry: entry)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button("Undo", systemImage: "arrow.uturn.backward") {
                                                    undo(entry)
                                                }
                                                .tint(.blue)

                                                Button("Delete", systemImage: "trash", role: .destructive) {
                                                    delete(entry)
                                                }
                                            }
                                            .contextMenu {
                                                Button("Undo ignore", systemImage: "arrow.uturn.backward") {
                                                    undo(entry)
                                                }

                                                Button("Delete", systemImage: "trash", role: .destructive) {
                                                    delete(entry)
                                                }
                                            }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("Auto-ignored")

                                    Spacer()

                                    Button("Clear all", role: .destructive) {
                                        isConfirmingClear = true
                                    }
                                    .font(.caption.weight(.medium))
                                    .textCase(nil)
                                    .contentShape(.rect)
                                    .padding(.vertical, 6)
                                    .confirmationDialog(
                                        "Delete all auto-ignored messages?",
                                        isPresented: $isConfirmingClear,
                                        titleVisibility: .visible
                                    ) {
                                        Button(
                                            autoIgnored.count == 1
                                                ? "Delete 1 message"
                                                : "Delete \(autoIgnored.count) messages",
                                            role: .destructive
                                        ) {
                                            clearAutoIgnored()
                                        }

                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text(
                                            "The learned patterns are kept, so new look-alike messages stay out of Review. This removes only the ignored history."
                                        )
                                    }
                                }
                            } footer: {
                                Text(
                                    "These match a message pattern you ignored. Undo puts one back in Review and forgets the pattern. Deleting or clearing removes the history but keeps the pattern."
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

    private func delete(_ entry: LedgerEntry) {
        try? inboxService.deleteAutoIgnored(entry)
        reload()
    }

    private func clearAutoIgnored() {
        _ = try? inboxService.deleteAllAutoIgnored()
        reload()
    }

    private func dismiss(_ message: UnparsedMessage) {
        try? inboxService.dismiss(message)
    }

    private func clearUnparsed() {
        _ = try? inboxService.deleteAllUnparsed()
        reload()
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
        HStack(spacing: 12) {
            Image(systemName: "questionmark.bubble")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(.orange.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.rawText.isEmpty ? "Original text wasn't saved" : message.rawText)
                    .font(.caption)
                    .lineLimit(3)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
        var parts: [String] = []

        if !entry.channelName.isEmpty {
            parts.append("via \(entry.channelName)")
        }

        if entry.isConfirmationOnly {
            parts.append("from a bank receipt")
        }

        if entry.account == nil {
            parts.append("Needs account")
        }

        parts.append(when)
        return parts.joined(separator: " · ")
    }
}
