//
//  TagPickerSheet.swift
//  EntryFormFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Multi-select tag picker with inline creation, shared by the single-line and split editors.
public struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TagService.self) private var tagService

    @Binding private var selection: Set<UUID>
    private let onCreated: (Tag) -> Void

    @State private var tags: [Tag] = []
    @State private var search = ""
    @State private var newName = ""
    @State private var errorMessage: String?

    public init(selection: Binding<Set<UUID>>, onCreated: @escaping (Tag) -> Void = { _ in }) {
        _selection = selection
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            List {
                if !filteredTags.isEmpty {
                    Section("Tags") {
                        ForEach(filteredTags) { tag in
                            Button {
                                toggle(tag)
                            } label: {
                                TagPickRow(tag: tag, isSelected: selection.contains(tag.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("New tag") {
                    HStack {
                        TextField("Name", text: $newName)

                        Button("Add", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if filteredTags.isEmpty, selection.isEmpty {
                    Section {
                        Text("No tags yet. Create one to track an assignment, an invoice or any purpose.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search tags")
            .navigationTitle("Tags")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .task { reload() }
        }
    }

    private var filteredTags: [Tag] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return tags.filter { tag in
            guard tag.isOpen || selection.contains(tag.id) else {
                return false
            }

            return needle.isEmpty || tag.name.localizedStandardContains(needle)
        }
    }

    private func reload() {
        do {
            tags = try tagService.fetchTags(includeClosed: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ tag: Tag) {
        if selection.contains(tag.id) {
            selection.remove(tag.id)
        } else {
            selection.insert(tag.id)
        }
    }

    private func create() {
        do {
            let tag = try tagService.createTag(name: newName)
            newName = ""
            errorMessage = nil
            tags = try tagService.fetchTags(includeClosed: true)
            selection.insert(tag.id)
            onCreated(tag)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TagPickRow: View {
    let tag: Tag
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tag.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ManotiColor.forHex(tag.colorHex))
                .frame(width: 22)

            Text(tag.name)

            if !tag.isOpen {
                Text("Closed")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
        .accessibilityLabel(isSelected ? "\(tag.name), selected" : tag.name)
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
