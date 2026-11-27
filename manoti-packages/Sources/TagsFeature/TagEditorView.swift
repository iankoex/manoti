//
//  TagEditorView.swift
//  TagsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

struct TagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TagService.self) private var tagService

    private let tag: Tag?

    @State private var name: String
    @State private var colorHex: String
    @State private var symbolName: String
    @State private var note: String
    @State private var errorMessage: String?

    init(tag: Tag?) {
        self.tag = tag
        _name = State(initialValue: tag?.name ?? "")
        _colorHex = State(initialValue: tag?.colorHex ?? ManotiPalette.accountColours[0])
        _symbolName = State(initialValue: tag?.symbolName ?? "tag")
        _note = State(initialValue: tag?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag") {
                    TextField("Name", text: $name)
                    TextField("Note (optional)", text: $note)
                }

                Section("Appearance") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(ManotiPalette.accountColours, id: \.self) { hex in
                            colourSwatch(hex)
                        }
                    }
                    .padding(.vertical, 4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(symbolNames, id: \.self) { symbol in
                            symbolSwatch(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(tag == nil ? "New tag" : "Edit tag")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var symbolNames: [String] {
        ["tag", "doc.text", "briefcase", "airplane", "building.2", "cart", "tray.full", "folder"]
    }

    private func colourSwatch(_ hex: String) -> some View {
        let tint = ManotiColor.forHex(hex)

        return Circle()
            .fill(tint)
            .frame(width: 30, height: 30)
            .overlay {
                if colorHex == hex {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .onTapGesture { colorHex = hex }
            .accessibilityLabel("Colour")
    }

    private func symbolSwatch(_ symbol: String) -> some View {
        let tint = ManotiColor.forHex(colorHex)

        return Image(systemName: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(symbolName == symbol ? .white : tint)
            .frame(width: 36, height: 36)
            .background(
                symbolName == symbol ? tint : tint.opacity(0.12),
                in: .rect(cornerRadius: 10)
            )
            .onTapGesture { symbolName = symbol }
            .accessibilityLabel(symbol)
    }

    private func save() {
        do {
            if let tag {
                try tagService.updateTag(
                    tag,
                    name: name,
                    colorHex: colorHex,
                    symbolName: symbolName,
                    note: note
                )
            } else {
                try tagService.createTag(
                    name: name,
                    colorHex: colorHex,
                    symbolName: symbolName,
                    note: note
                )
            }

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
