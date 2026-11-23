//
//  CategoryDrillDownPicker.swift
//  QuickAddFeature
//

import AppModels
import Modifiers
import SwiftUI

/// Small strings used by the drill-down picker, kept separate so they are testable.
enum CategoryDrillDownText {
    static func groupCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "category" : "categories")"
    }

    /// A single group is not worth a separate step; show its categories immediately.
    static func usesGroupStep(groupCount: Int) -> Bool {
        groupCount > 1
    }
}

/// Two-level category picker: groups first, then the categories inside one group.
///
/// The panel always has room for four rows, so moving between groups never resizes the
/// sheet. The selected category stays visible above the list.
struct CategoryDrillDownPicker: View {
    let groups: [CategoryGroup]
    let kind: CategoryKind
    @Binding var selectedCategoryID: UUID?
    let selectedCategory: SpendingCategory?

    @State private var expandedGroupID: UUID?

    private let rowHeight: CGFloat = 46
    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            panel
        }
        .onChange(of: kind) { _, _ in
            expandedGroupID = nil
        }
        .sensoryFeedback(.selection, trigger: selectedCategoryID)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Category")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let selectedCategory {
                Button {
                    selectedCategoryID = selectedCategory.id
                    expandedGroupID = selectedCategory.group?.id
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selectedCategory.symbolName)
                            .font(.caption2)
                        Text(selectedCategory.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(ManotiColor.forHex(selectedCategory.colorHex))
                }
                .buttonStyle(.plain)

                Button {
                    selectedCategoryID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear category")
            } else {
                Text("Choose")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var panel: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let activeGroup {
                    if CategoryDrillDownText.usesGroupStep(groupCount: visibleGroups.count) {
                        backRow
                        divider
                    }

                    ForEach(categories(in: activeGroup)) { category in
                        categoryRow(category)
                    }
                } else if visibleGroups.isEmpty {
                    Text("No \(kind.displayName.lowercased()) categories yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(height: rowHeight)
                } else {
                    ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                        groupRow(group)
                        if index < visibleGroups.count - 1 {
                            divider
                        }
                    }
                }
            }
            .id(activeGroup?.id.uuidString ?? "groups")
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: rowHeight * 4 + 2)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: cornerRadius))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .animation(.snappy(duration: 0.2), value: activeGroup?.id)
    }

    private var visibleGroups: [CategoryGroup] {
        groups.filter { !$0.isArchived && !matchingCategories(in: $0).isEmpty }
    }

    /// With one matching group (currently Income), the categories are the first level.
    private var activeGroup: CategoryGroup? {
        if visibleGroups.count == 1 {
            return visibleGroups.first
        }

        guard let expandedGroupID else {
            return nil
        }

        return visibleGroups.first { $0.id == expandedGroupID }
    }

    private var backRow: some View {
        Button {
            expandedGroupID = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 26)

                Text("All groups")
                    .font(.subheadline.weight(.medium))

                Spacer()

                if let activeGroup {
                    Text(activeGroup.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to all groups")
    }

    private func groupRow(_ group: CategoryGroup) -> some View {
        let tint = ManotiColor.forHex(group.colorHex)
        let count = matchingCategories(in: group).count

        return Button {
            expandedGroupID = group.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: group.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .frame(width: 26)

                Text(group.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(CategoryDrillDownText.groupCount(count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows \(group.name) categories.")
    }

    private func categoryRow(_ category: SpendingCategory) -> some View {
        let tint = ManotiColor.forHex(category.colorHex)
        let isSelected = selectedCategoryID == category.id

        return Button {
            selectedCategoryID = isSelected ? nil : category.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .frame(width: 26)

                Text(category.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .background(isSelected ? tint.opacity(0.12) : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 52)
    }

    private func matchingCategories(in group: CategoryGroup) -> [SpendingCategory] {
        group.visibleCategories.filter { $0.kind == kind }
    }

    private func categories(in group: CategoryGroup) -> [SpendingCategory] {
        matchingCategories(in: group)
    }
}
