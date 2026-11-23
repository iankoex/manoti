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
    @State private var selected: LedgerEntry?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty && unparsed.isEmpty {
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
        if selected?.isSoftDeleted == true {
            selected = nil
        }
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(entry.occurredAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                    if entry.account == nil {
                        Text("· Needs account")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            AmountText(Money(minorUnits: entry.amountMinor, currency: entry.currency), style: .subheadline)
        }
        .contentShape(.rect)
    }

    private var title: String {
        entry.payee.isEmpty ? entry.kind.displayName : entry.payee
    }
}
