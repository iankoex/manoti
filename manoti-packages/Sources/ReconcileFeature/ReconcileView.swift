//
//  ReconcileView.swift
//  ReconcileFeature
//

import AppModels
import AppServices
import LedgerFeature
import Modifiers
import SwiftData
import SwiftUI

/// Reviews the newest reconciliation session and offers the small set of safe actions.
///
/// The screen is pushed by Settings, so it deliberately has no navigation stack of its own.
public struct ReconcileView: View {
    private let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ReconciliationService.self) private var reconciliationService
    @Environment(AppService.self) private var appService
    @Environment(\.manotiAmountsHidden) private var amountsHidden

    @State private var session: ReconcileSession?
    @State private var messages: [ReconcileMessage] = []
    @State private var appOnlyEntries: [LedgerEntry] = []
    @State private var ignoredEntries: [LedgerEntry] = []
    @State private var matchedEntries: [UUID: LedgerEntry] = [:]
    @State private var summary: ReconcileSummary?
    @State private var summarySessionID: UUID?
    @State private var selectedBucket: ReconcileBucket = .matched
    @State private var selectedPreset: ReconcilePeriodPreset = .today
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    public init(showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManotiSpacing.large) {
                if isLoading && session == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, ManotiSpacing.extraLarge)
                } else if let session {
                    summaryCard(session)

                    bucketPicker
                    bucketContent(session)

                    if isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, ManotiSpacing.regular)
            .padding(.bottom, 88)
        }
        .background(.background)
        .navigationTitle("Reconcile")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                newSessionMenu
            }
        }
        .alert(
            "Could not update reconciliation",
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

    // MARK: - Summary

    private func summaryCard(_ session: ReconcileSession) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            HStack(spacing: ManotiSpacing.small) {
                Text("Latest session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                stateBadge(for: session)
            }

            Text(
                ReconcileFormatting.sessionSubtitle(
                    periodStart: session.periodStart,
                    periodEnd: session.periodEnd,
                    messageCount: messages.count,
                    calendar: calendar
                )
            )
            .font(.headline)

            if session.isFinalised {
                Text(summaryText(for: session))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(ReconcileFormatting.unfinalisedExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if amountsHidden {
                Label("Amounts hidden", systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !session.isFinalised {
                Button {
                    finalise(session)
                } label: {
                    Label("Finalise", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isBusy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.thinMaterial, in: .rect(cornerRadius: 20))
    }

    private func stateBadge(for session: ReconcileSession) -> some View {
        let tint: Color = session.isFinalised ? .green : .orange

        return Text(session.isFinalised ? "Finalised" : "In progress")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, ManotiSpacing.small)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
    }

    private func summaryText(for session: ReconcileSession) -> String {
        if let summary, summarySessionID == session.id {
            return summary.displayText
        }

        return ReconciliationService.displayText(
            messageCount: messages.count,
            matchedCount: matchedMessages.count,
            messageOnlyCount: missingMessages.count,
            appOnlyCount: appOnlyEntries.count,
            possibleCount: possibleMessages.count,
            ignoredCount: session.ignoredEntryIDs.count,
            missingTimeCount: messages.filter { $0.receivedAt == nil }.count
        )
    }

    // MARK: - Buckets

    private var bucketPicker: some View {
        Picker("Bucket", selection: $selectedBucket) {
            ForEach(availableBuckets) { bucket in
                Text(ReconcileFormatting.bucketTitle(for: bucket, count: count(for: bucket)))
                    .tag(bucket)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func bucketContent(_ session: ReconcileSession) -> some View {
        switch selectedBucket {
            case .matched:
                matchedBucket
            case .missing:
                missingBucket
            case .notInMessages:
                notInMessagesBucket(session)
            case .possible:
                possibleBucket
        }
    }

    @ViewBuilder
    private var matchedBucket: some View {
        if session?.isFinalised == false {
            emptyBucket("Finalise this session to see which messages matched the ledger.")
        } else if matchedMessages.isEmpty {
            emptyBucket("No messages matched a ledger entry yet.")
        } else {
            ForEach(matchedMessages, id: \.id) { message in
                messageCard(message, bucket: .matched)
            }
        }
    }

    @ViewBuilder
    private var missingBucket: some View {
        if session?.isFinalised == false {
            emptyBucket("Finalise this session to see messages that are missing from the ledger.")
        } else {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                Text(ReconcileFormatting.importExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if missingMessages.isEmpty {
                emptyBucket("No collected messages are missing from the ledger.")
            } else {
                ForEach(missingMessages, id: \.id) { message in
                    messageCard(message, bucket: .missing)
                }
            }
        }
    }

    @ViewBuilder
    private var possibleBucket: some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            Text(ReconcileFormatting.possibleExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if possibleMessages.isEmpty {
            emptyBucket("No possible duplicates need a decision.")
        } else {
            ForEach(possibleMessages, id: \.id) { message in
                messageCard(message, bucket: .possible)
            }
        }
    }

    private func notInMessagesBucket(_ session: ReconcileSession) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.medium) {
            Text(ReconcileFormatting.notInMessagesExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !session.isFinalised {
                emptyBucket("Finalise this session to see posted entries that no message matched.")
            } else if appOnlyEntries.isEmpty {
                emptyBucket("Every posted entry in this period is matched or ignored.")
            } else {
                ForEach(appOnlyEntries, id: \.id) { entry in
                    appEntryCard(entry, session: session)
                }
            }

            if !ignoredEntries.isEmpty {
                ignoredSection(session)
            }
        }
    }

    private func appEntryCard(_ entry: LedgerEntry, session: ReconcileSession) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            LedgerEntryRowView(entry: entry)

            HStack(alignment: .center, spacing: ManotiSpacing.small) {
                Text(ReconcileFormatting.ignoreExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: ManotiSpacing.small)

                Button("Ignore", systemImage: "eye.slash") {
                    ignore(entry, in: session)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    private func ignoredSection(_ session: ReconcileSession) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack(spacing: ManotiSpacing.small) {
                Text("Ignored")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(ignoredEntries.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ManotiSpacing.small)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: .capsule)
            }

            ForEach(ignoredEntries, id: \.id) { entry in
                VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                    LedgerEntryRowView(entry: entry)

                    HStack {
                        Spacer()

                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            unignore(entry, in: session)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }
                }
                .padding(ManotiSpacing.regular)
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
            }
        }
    }

    // MARK: - Message card

    private func messageCard(_ message: ReconcileMessage, bucket: ReconcileBucket) -> some View {
        VStack(alignment: .leading, spacing: ManotiSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: ManotiSpacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(messageTitle(message))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(messageContext(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: ManotiSpacing.small)

                messageAmount(message)
            }

            if !message.reference.isEmpty {
                Text("Ref \(message.reference)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if message.feeMinor != 0 {
                HStack(spacing: ManotiSpacing.small) {
                    Text("Fee")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    MaskedAmountText(
                        Money(minorUnits: message.feeMinor, currency: message.currency),
                        style: .caption2
                    )
                }
            }

            if bucket == .possible {
                Label("Possible duplicate", systemImage: "questionmark.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if bucket == .matched {
                matchedEntryLine(message)
            }

            if bucket == .missing || bucket == .possible {
                Button("Import", systemImage: "tray.and.arrow.down") {
                    importMessage(message)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || !canImport(message))

                if !canImport(message) {
                    Text("This message could not be read, so it cannot be imported.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ManotiSpacing.regular)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func messageAmount(_ message: ReconcileMessage) -> some View {
        if message.amountMinor > 0 {
            MaskedAmountText(
                Money(minorUnits: message.amountMinor, currency: message.currency),
                style: .subheadline.weight(.semibold)
            )
        } else {
            Text("No amount")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func matchedEntryLine(_ message: ReconcileMessage) -> some View {
        if let id = message.matchedEntryID {
            let description = matchedEntries[id].map(entryDescription) ?? "Entry not found"

            VStack(alignment: .leading, spacing: 2) {
                Text("Matched entry")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(description)
                    .font(.caption)
            }
        }
    }

    private func messageTitle(_ message: ReconcileMessage) -> String {
        let payee = message.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        if !payee.isEmpty {
            return payee
        }

        if let kind = message.parsedKind {
            return kind.displayName
        }

        return "Unread message"
    }

    private func messageContext(_ message: ReconcileMessage) -> String {
        var parts: [String] = []

        if let kind = message.parsedKind {
            parts.append(kind.displayName)
        }

        let date = message.receivedAt ?? message.occurredAt ?? message.createdAt
        parts.append(date.formatted(date: .abbreviated, time: .shortened))

        if !message.sender.isEmpty {
            parts.append(message.sender)
        }

        return parts.joined(separator: " · ")
    }

    private func entryDescription(_ entry: LedgerEntry) -> String {
        var parts: [String] = []

        let payee = entry.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        if !payee.isEmpty {
            parts.append(payee)
        } else if let category = entry.primaryCategory {
            parts.append(category.name)
        } else {
            parts.append(entry.kind.displayName)
        }

        if let account = entry.account {
            parts.append(account.displayName)
        }

        return parts.joined(separator: " · ")
    }

    private func canImport(_ message: ReconcileMessage) -> Bool {
        (message.classification == .missing || message.classification == .possible)
            && message.parsedKind != nil
            && message.amountMinor > 0
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: ManotiSpacing.large) {
            EmptyStateView(
                symbolName: "arrow.triangle.2.circlepath",
                title: "No reconciliation session yet",
                message: ReconcileFormatting.emptyStateMessage
            )

            Picker("Period", selection: $selectedPreset) {
                ForEach(ReconcilePeriodPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Button {
                startSession(selectedPreset)
            } label: {
                Label("Start a session", systemImage: "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isBusy)

            if isWorking {
                ProgressView()
            }

            Text("Starting a session only prepares a period. The Messages Shortcut adds the messages.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, ManotiSpacing.large)
    }

    // MARK: - Toolbar

    private var newSessionMenu: some View {
        Menu {
            Section("New session") {
                Button("Today") {
                    startSession(.today)
                }

                Button("Last 7 days") {
                    startSession(.lastSevenDays)
                }
            }
        } label: {
            Label("New session", systemImage: "plus.circle")
        }
        .disabled(isBusy)
    }

    // MARK: - Derived rows

    private var matchedMessages: [ReconcileMessage] {
        messages.filter { $0.classification == .matched }
    }

    private var missingMessages: [ReconcileMessage] {
        messages.filter { $0.classification == .missing }
    }

    private var possibleMessages: [ReconcileMessage] {
        messages.filter { $0.classification == .possible }
    }

    private var availableBuckets: [ReconcileBucket] {
        var buckets: [ReconcileBucket] = [.matched, .missing, .notInMessages]
        if !possibleMessages.isEmpty {
            buckets.append(.possible)
        }
        return buckets
    }

    private func count(for bucket: ReconcileBucket) -> Int {
        switch bucket {
            case .matched:
                matchedMessages.count
            case .missing:
                missingMessages.count
            case .notInMessages:
                appOnlyEntries.count
            case .possible:
                possibleMessages.count
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = appService.weekStartsOn
        return calendar
    }

    private var isBusy: Bool {
        isLoading || isWorking
    }

    // MARK: - Loading

    private func reload() {
        isLoading = session == nil
        defer { isLoading = false }

        do {
            let latest = try reconciliationService.latestSession()

            guard let latest else {
                session = nil
                messages = []
                appOnlyEntries = []
                ignoredEntries = []
                matchedEntries = [:]
                summary = nil
                summarySessionID = nil
                errorMessage = nil
                return
            }

            if session?.id != latest.id {
                summary = nil
                summarySessionID = nil
            }

            session = latest
            messages = try fetchMessages(for: latest)
            ignoredEntries = try fetchIgnoredEntries(for: latest)

            if latest.isFinalised {
                appOnlyEntries = try reconciliationService.appOnlyEntries(in: latest)
                matchedEntries = try fetchMatchedEntries(for: messages)
            } else {
                appOnlyEntries = []
                matchedEntries = [:]
            }

            if !availableBuckets.contains(selectedBucket) {
                selectedBucket = .matched
            }

            errorMessage = nil
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func fetchMessages(for session: ReconcileSession) throws -> [ReconcileMessage] {
        try reconciliationService.messages(in: session)
    }

    private func fetchMatchedEntries(for messages: [ReconcileMessage]) throws -> [UUID: LedgerEntry] {
        let ids = Set(messages.filter { $0.classification == .matched }.compactMap(\.matchedEntryID))
        var entries: [UUID: LedgerEntry] = [:]

        for id in ids {
            if let entry = try entry(withID: id) {
                entries[id] = entry
            }
        }

        return entries
    }

    private func fetchIgnoredEntries(for session: ReconcileSession) throws -> [LedgerEntry] {
        var entries: [LedgerEntry] = []

        for id in session.ignoredEntryIDs {
            if let entry = try entry(withID: id) {
                entries.append(entry)
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func entry(withID id: UUID) throws -> LedgerEntry? {
        try reconciliationService.entry(withID: id)
    }

    // MARK: - Actions

    private func startSession(_ preset: ReconcilePeriodPreset) {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            selectedPreset = preset

            let interval = preset.dateInterval(calendar: calendar, now: .now)
            let end = interval.end > interval.start ? interval.end : interval.start.addingTimeInterval(60)

            let created = try reconciliationService.startSession(
                token: "ui-\(UUID().uuidString)",
                periodStart: interval.start,
                periodEnd: end
            )

            session = created
            summary = nil
            summarySessionID = nil
            selectedBucket = .matched
            reload()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func finalise(_ session: ReconcileSession) {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            summary = try reconciliationService.finalise(session)
            summarySessionID = session.id
            reload()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func importMessage(_ message: ReconcileMessage) {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try reconciliationService.importMessage(message)
            invalidateSummarySnapshot()
            reload()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func ignore(_ entry: LedgerEntry, in session: ReconcileSession) {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try reconciliationService.ignore(appEntry: entry, in: session)
            invalidateSummarySnapshot()
            reload()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func unignore(_ entry: LedgerEntry, in session: ReconcileSession) {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try reconciliationService.unignore(appEntry: entry, in: session)
            invalidateSummarySnapshot()
            reload()
        } catch {
            errorMessage = errorText(error)
        }
    }

    private func invalidateSummarySnapshot() {
        summary = nil
        summarySessionID = nil
    }

    private func errorText(_ error: Error) -> String {
        guard let reconcileError = error as? ReconcileError else {
            return error.localizedDescription
        }

        switch reconcileError {
            case .invalidPeriod:
                return "Choose a period that ends after it starts."
            case .sessionFinalised:
                return "This session has already been finalised."
            case .unrecognisedMessage:
                return "This message could not be read, so it cannot be imported."
            case .transferNeedsPairing:
                return "Pair this transfer on the Transfers screen instead."
        }
    }

    // MARK: - Small views

    private func emptyBucket(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ManotiSpacing.regular)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
    }
}
