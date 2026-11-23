//
//  CategoriesView.swift
//  SettingsFeature
//

import AppModels
import AppServices
import Modifiers
import SwiftUI

/// Grouped category list pushed from Settings.
struct CategoriesView: View {
    @Environment(AppService.self) private var appService
    @Environment(CategoryService.self) private var categoryService

    @State private var groups: [CategoryGroup] = []
    @State private var editorTarget: CategoryEditorTarget?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !hasAnyCategory {
                emptyState
            } else {
                ForEach(visibleGroups) { group in
                    groupSection(for: group)
                }

                if !archivedCategories.isEmpty {
                    archivedSection
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorTarget = CategoryEditorTarget(category: nil)
                } label: {
                    Label("Add category", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            CategoryEditorView(
                category: target.category,
                groups: groups,
                categories: groups.flatMap(\.sortedCategories),
                displayCurrency: appService.displayCurrency
            )
        }
        .alert(
            "Could not update category",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onManotiDataChange { reload() }
    }

    private var visibleGroups: [CategoryGroup] {
        groups.filter { !$0.isArchived && !$0.visibleCategories.isEmpty }
    }

    private var archivedCategories: [SpendingCategory] {
        groups.flatMap(\.sortedCategories).filter(\.isArchived)
    }

    private var hasAnyCategory: Bool {
        groups.contains { !$0.sortedCategories.isEmpty }
    }

    private func groupSection(for group: CategoryGroup) -> some View {
        Section {
            ForEach(group.visibleCategories) { category in
                categoryRow(category)
            }
        } header: {
            Label {
                Text(group.name)
            } icon: {
                Image(systemName: group.symbolName)
                    .foregroundStyle(ManotiColor.forHex(group.colorHex))
            }
        }
    }

    private var archivedSection: some View {
        Section {
            ForEach(archivedCategories) { category in
                categoryRow(category)
            }
        } header: {
            Text("Archived")
        } footer: {
            Text("Archived categories keep their history but are hidden from pickers and suggestions.")
        }
    }

    private func categoryRow(_ category: SpendingCategory) -> some View {
        Button {
            editorTarget = CategoryEditorTarget(category: category)
        } label: {
            CategoryRow(category: category, displayCurrency: appService.displayCurrency)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if category.isArchived {
                Button("Unarchive", systemImage: "tray.and.arrow.up") {
                    setArchived(category, false)
                }
            } else {
                Button("Archive", systemImage: "archivebox", role: .destructive) {
                    setArchived(category, true)
                }
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("No categories yet", systemImage: "square.grid.2x2")
                    .font(.headline)

                Text(
                    "Categories group spending and power budgets, insights and message suggestions."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    editorTarget = CategoryEditorTarget(category: nil)
                } label: {
                    Label("Add a category", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 8)
        }
    }

    private func setArchived(_ category: SpendingCategory, _ archived: Bool) {
        do {
            try categoryService.setArchived(category, archived)
            reload()
        } catch {
            errorMessage = "The category could not be updated."
        }
    }

    private func reload() {
        groups = (try? categoryService.fetchAllGroups()) ?? []
    }
}

private struct CategoryRow: View {
    let category: SpendingCategory
    let displayCurrency: Currency

    @Environment(\.manotiAmountsHidden) private var amountsHidden

    var body: some View {
        let tint = ManotiColor.forHex(category.colorHex)

        HStack(spacing: ManotiSpacing.medium) {
            Image(systemName: category.symbolName)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name)

                    if category.isFixed {
                        fixedBadge(tint: tint)
                    }
                }

                if let monthlyDefaultMinor = category.monthlyDefaultMinor, !amountsHidden {
                    MaskedAmountText(
                        Money(minorUnits: monthlyDefaultMinor, currency: displayCurrency),
                        style: .caption,
                        colour: .secondary
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func fixedBadge(tint: Color) -> some View {
        Text("Fixed")
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

private struct CategoryEditorTarget: Identifiable {
    let id = UUID()
    let category: SpendingCategory?
}
