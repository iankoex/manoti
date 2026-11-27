//
//  ManotiWidgets.swift
//  ManotiWidgets
//

import Foundation
import SwiftUI
import WidgetKit

/// Mirrors `WidgetSnapshot` in `AppServices`; the widget target deliberately has no package
/// dependency, so it reads only this small JSON file from the shared app group.
private struct WidgetSnapshot: Decodable {
    let updatedAt: Date
    let monthSpendText: String
    let safeToSpendText: String
    let isPrivacyModeEnabled: Bool
}

private enum SnapshotStore {
    static let appGroupIdentifier = "group.com.iankoex.manoti"
    static let filename = "widget-snapshot.json"

    static func load() -> WidgetSnapshot? {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            return nil
        }

        let url =
            container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

private struct ManotiEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    static let placeholder = ManotiEntry(
        date: .now,
        snapshot: WidgetSnapshot(
            updatedAt: .now,
            monthSpendText: "KES 2,130.00",
            safeToSpendText: "KES 1,305.55",
            isPrivacyModeEnabled: false
        )
    )

    static let empty = ManotiEntry(date: .now, snapshot: nil)
}

private struct ManotiTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ManotiEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ManotiEntry) -> Void) {
        completion(ManotiEntry(date: .now, snapshot: SnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ManotiEntry>) -> Void) {
        let entry = ManotiEntry(date: .now, snapshot: SnapshotStore.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct ManotiWidgetView: View {
    let entry: ManotiEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.16),
                    Color(red: 0.10, green: 0.16, blue: 0.26),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
            case .systemSmall:
                small(snapshot)
            default:
                medium(snapshot)
        }
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(snapshot)

            Spacer(minLength: 0)

            Text("This month")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))

            Text(snapshot.monthSpendText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let updated = updatedText(snapshot) {
                Text(updated)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(snapshot)

            HStack(alignment: .top, spacing: 14) {
                metric("This month", snapshot.monthSpendText, size: 21)
                Divider()
                    .overlay(.white.opacity(0.2))
                metric("Safe to spend", snapshot.safeToSpendText, size: 17)
            }

            Spacer(minLength: 0)

            if let updated = updatedText(snapshot) {
                Text(updated)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func header(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.pie.fill")
                .font(.caption2)
                .foregroundStyle(Color(red: 0.37, green: 0.63, blue: 1))

            Text("Manoti")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 0)

            if snapshot.isPrivacyModeEnabled {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func metric(_ title: String, _ value: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)

            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func updatedText(_ snapshot: WidgetSnapshot) -> String? {
        guard !snapshot.isPrivacyModeEnabled else {
            return nil
        }

        return "Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "chart.pie.fill")
                .font(.title3)
                .foregroundStyle(Color(red: 0.37, green: 0.63, blue: 1))

            Text("Manoti")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Open Manoti once to fill this widget.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ManotiSummaryWidget: Widget {
    let kind = "ManotiSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ManotiTimelineProvider()) { entry in
            ManotiWidgetView(entry: entry)
        }
        .configurationDisplayName("Manoti Summary")
        .description("Net worth, this month's spending and safe to spend.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    ManotiSummaryWidget()
} timeline: {
    ManotiEntry.placeholder
}

#Preview(as: .systemMedium) {
    ManotiSummaryWidget()
} timeline: {
    ManotiEntry.placeholder
}
