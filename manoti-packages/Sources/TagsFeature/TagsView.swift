//
//  TagsView.swift
//  TagsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Every tag, open first, with its balance. A tag never moves money; these numbers come from
/// the lines that carry it.
public struct TagsView: View {
    @Environment(TagService.self) private var tagService
    @Environment(AppService.self) private var appService

    @State private var openTags: [Tag] = []
    @State private var closedTags: [Tag] = []
    @State private var summaries: [UUID: TagSummary] = [:]
    @State private var editorTarget: TagEditorTarget?
    @State private var deleteTarget: Tag?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        List {
            if openTags.isEmpty, closedTags.isEmpty {
                emptyState
            } else {
                if !openTags.isEmpty {
                    Section("Open") {
                        ForEach(openTags) { tag in
                            row(tag)
                        }
                    }
                }

                if !closedTags.isEmpty {
                    Section("Closed") {
                        ForEach(closedTags) { tag in
                            row(tag)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New tag", systemImage: "plus") {
                    editorTarget = .create
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            TagEditorView(tag: target.tag)
        }
        .alert(
            "Could not delete tag",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \($0.name)?" } ?? "Delete tag?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: confirmDelete)
        } message: {
            Text("A tag used by a transaction cannot be deleted. Close it instead.")
        }
        .onManotiDataChange { reload() }
        .task { reload() }
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label("Tag money for a purpose", systemImage: "tag")
            } description: {
                Text(
                    "Tag an assignment, an invoice or a quotation, then see what came in, what went out and what is left."
                )
            }
        }
    }

    private func row(_ tag: Tag) -> some View {
        NavigationLink {
            TagDetailView(tag: tag)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tag.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ManotiColor.forHex(tag.colorHex))
                    .frame(width: 30, height: 30)
                    .background(ManotiColor.forHex(tag.colorHex).opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.name)
                        .font(.subheadline.weight(.medium))

                    if let summary = summaries[tag.id] {
                        Text(caption(for: summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let summary = summaries[tag.id] {
                    AmountText(
                        tag.isOpen ? summary.balance : summary.profit,
                        style: .subheadline.weight(.semibold)
                    )
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteTarget = tag
            }

            Button("Edit", systemImage: "pencil") {
                editorTarget = .edit(tag)
            }
            .tint(.blue)

            if tag.isOpen {
                Button("Close", systemImage: "lock") {
                    setStatus(tag, close: true)
                }
                .tint(.orange)
            } else {
                Button("Reopen", systemImage: "lock.open") {
                    setStatus(tag, close: false)
                }
                .tint(.blue)
            }
        }
    }

    private func caption(for summary: TagSummary) -> String {
        "\(summary.received.formatted()) in · \(summary.spent.formatted()) out"
    }

    private func reload() {
        let all = (try? tagService.fetchTags(includeClosed: true)) ?? []
        openTags = all.filter(\.isOpen)
        closedTags = all.filter { !$0.isOpen }

        var result: [UUID: TagSummary] = [:]
        let currency = appService.displayCurrency

        for tag in all {
            result[tag.id] = try? tagService.summary(for: tag, displayCurrency: currency)
        }

        summaries = result
    }

    private func setStatus(_ tag: Tag, close: Bool) {
        do {
            if close {
                try tagService.closeTag(tag)
            } else {
                try tagService.reopenTag(tag)
            }

            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDelete() {
        guard let tag = deleteTarget else {
            return
        }

        deleteTarget = nil

        do {
            try tagService.deleteTag(tag)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum TagEditorTarget: Identifiable {
    case create
    case edit(Tag)

    var tag: Tag? {
        switch self {
            case .create: nil
            case .edit(let tag): tag
        }
    }

    var id: String {
        switch self {
            case .create: "create"
            case .edit(let tag): tag.id.uuidString
        }
    }
}
