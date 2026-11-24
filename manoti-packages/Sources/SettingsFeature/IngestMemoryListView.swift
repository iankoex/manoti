//
//  IngestMemoryListView.swift
//  SettingsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Everything the Inbox has learned, so a wrong lesson can be seen and removed.
struct IngestMemoryListView: View {
    @Environment(InboxService.self) private var inboxService

    @State private var memories: [IngestMemory] = []

    var body: some View {
        List {
            if memories.isEmpty {
                Text(
                    "Nothing learned yet. Ignore a message in the Inbox to teach Manoti which messages to skip."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(memories) { memory in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(memory.sender.isEmpty ? "Unknown sender" : memory.sender)
                                .font(.subheadline.weight(.medium))

                            Spacer(minLength: 8)

                            Text(memory.reason.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(subtitle(for: memory))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Learned messages")
        .navigationBarTitleDisplayModeInlineCompat()
        .onManotiDataChange { reload() }
        .task { reload() }
    }

    private func subtitle(for memory: IngestMemory) -> String {
        let hits = memory.hitCount == 1 ? "1 message" : "\(memory.hitCount) messages"
        let when = memory.lastSeenAt.formatted(date: .abbreviated, time: .shortened)
        return "\(hits) · last \(when)"
    }

    private func reload() {
        memories = (try? inboxService.memories()) ?? []
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? inboxService.deleteMemory(memories[index])
        }

        reload()
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
