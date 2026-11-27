//
//  MaintenancePipeline.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import SwiftData

/// What one maintenance pass actually did.
nonisolated public struct MaintenanceReport: Equatable, Sendable {
    public let ranAt: Date
    public let outboxDrained: Int
    public let investmentsSettled: Int
    public let notificationsRefreshed: Bool
    public let widgetRefreshed: Bool

    public init(
        ranAt: Date,
        outboxDrained: Int,
        investmentsSettled: Int,
        notificationsRefreshed: Bool,
        widgetRefreshed: Bool
    ) {
        self.ranAt = ranAt
        self.outboxDrained = outboxDrained
        self.investmentsSettled = investmentsSettled
        self.notificationsRefreshed = notificationsRefreshed
        self.widgetRefreshed = widgetRefreshed
    }
}

/// The work that must follow a write, expressed against a single `ModelContext`.
///
/// The pipeline is deliberately `nonisolated`: it belongs to whichever isolation domain owns the
/// context it was built with. The app runs it on the main context from the UI and from App
/// Intents (`AppMaintenance`), while a `BGTask` runs it on a private context through
/// `MaintenanceWorker`. Keeping the pipeline isolation-agnostic is what lets background work run
/// without the main actor being available.
nonisolated public struct MaintenancePipeline {
    private let context: ModelContext
    private let defaults: UserDefaults

    public init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    // MARK: - Runs

    /// Runs the complete post-write pipeline. Safe to call from every intent and every save.
    ///
    /// `isStopped` lets a background task abandon the pass between stages when the system expires
    /// it, without forcing an actor hop to cancel a task. It defaults to Swift task cancellation,
    /// which is what the foreground and App Intent paths rely on.
    @discardableResult
    public func runAfterWrite(
        promptForNotifications: Bool = false,
        now: Date = Date(),
        isStopped: @Sendable () -> Bool = { Task.isCancelled }
    ) async -> MaintenanceReport {
        let repaired = stop(isStopped) ? 0 : repairEntryLines()
        _ = repaired
        let drained = stop(isStopped) ? 0 : drainPendingMessages()

        if !stop(isStopped) {
            runCorrelationRepairs()
        }

        let settled = settlePendingInvestments(now: now, isStopped: isStopped)
        let notificationsRefreshed = await refreshNotifications(
            promptForNotifications: promptForNotifications,
            isStopped: isStopped
        )
        let widgetRefreshed = refreshWidget(at: now, isStopped: isStopped)

        recordRun(at: now, isStopped: isStopped)

        await AppBackgroundScheduler.schedule()

        return MaintenanceReport(
            ranAt: now,
            outboxDrained: drained,
            investmentsSettled: settled,
            notificationsRefreshed: notificationsRefreshed,
            widgetRefreshed: widgetRefreshed
        )
    }

    /// Replays parked messages without touching notifications. Used at launch before the first
    /// frame, where awaiting the full pipeline is not possible.
    @discardableResult
    public func drainPendingMessages() -> Int {
        guard !Task.isCancelled else {
            return 0
        }

        let ingest = IngestService(context: context)
        return (try? IngestOutbox().drain(into: ingest)) ?? 0
    }

    /// Gives every expense and income without lines one uncategorised line for its full amount.
    /// Old CloudKit records and older backups can arrive line-less; this makes them safe to open.
    @discardableResult
    public func repairEntryLines() -> Int {
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && ($0.kindRaw == "expense" || $0.kindRaw == "income")
            }
        )

        guard let entries = try? context.fetch(descriptor) else {
            return 0
        }

        var repaired = 0

        for entry in entries where (entry.lines ?? []).isEmpty {
            let line = LedgerEntryLine(amountMinor: entry.amountMinor)
            context.insert(line)
            line.entry = entry
            entry.lines = [line]
            repaired += 1
        }

        if repaired > 0 {
            try? context.save()
        }

        return repaired
    }

    // MARK: - Correlation repairs

    /// Runs the one-time and idempotent correlation repairs. Exposed so tests can run them
    /// without the notifications and widget stages.
    @discardableResult
    public func runCorrelationRepairs() -> Int {
        seedIngestPayees() + rereadUnparsedMessages() + linkUnpairedTransfers()
    }

    /// Old message entries did not record the payee as parsed. Copying it once lets a late
    /// bank confirmation replace a generic biller with the real merchant.
    @discardableResult
    private func seedIngestPayees() -> Int {
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> {
                !$0.isSoftDeleted && $0.sourceRaw == "message" && $0.ingestPayee == ""
                    && $0.payee != ""
            }
        )

        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else {
            return 0
        }

        for entry in entries {
            entry.ingestPayee = entry.payee
        }

        try? context.save()
        return entries.count
    }

    /// Re-reads messages the parser once could not understand, once per shared-rules
    /// revision. A receipt that now matches an entry is consumed; a new movement is kept
    /// in the Inbox like any other.
    @discardableResult
    private func rereadUnparsedMessages() -> Int {
        // Kept as a literal: `SharedRulesService.revisionKey` is main-actor-isolated and
        // this pipeline runs without the main actor.
        let currentRevision = defaults.integer(forKey: "manoti.rulesRevision")
        guard currentRevision > 0 else {
            return 0
        }

        let marker = "manoti.unparsedReprocessRevision"
        guard defaults.integer(forKey: marker) != currentRevision else {
            return 0
        }

        let descriptor = FetchDescriptor<UnparsedMessage>(
            predicate: #Predicate<UnparsedMessage> {
                !$0.isDismissed && $0.rawText != ""
            }
        )

        guard let messages = try? context.fetch(descriptor), !messages.isEmpty else {
            defaults.set(currentRevision, forKey: marker)
            return 0
        }

        let ingest = IngestService(context: context)
        var consumed = 0

        for message in messages {
            guard
                let outcome = try? ingest.ingest(
                    text: message.rawText,
                    sender: message.sender.isEmpty ? nil : message.sender,
                    receivedAt: message.receivedAt
                )
            else {
                continue
            }

            if outcome.status != .unrecognised {
                context.delete(message)
                consumed += 1
            }
        }

        if context.hasChanges {
            try? context.save()
        }

        defaults.set(currentRevision, forKey: marker)
        return consumed
    }

    /// Links existing unpaired transfer legs whose references agree. Amount-and-time-only
    /// candidates stay for the user to confirm in Transfers.
    @discardableResult
    private func linkUnpairedTransfers() -> Int {
        let descriptor = FetchDescriptor<LedgerEntry>(
            sortBy: [SortDescriptor(\LedgerEntry.occurredAt, order: .reverse)]
        )

        guard let entries = try? context.fetch(descriptor) else {
            return 0
        }

        let legs = entries.filter {
            $0.kind.isTransferLeg && $0.transfer == nil && $0.isPosted && $0.account != nil
        }

        var linked = 0

        for leg in legs {
            guard leg.transfer == nil else {
                continue
            }

            let oppositeKind: LedgerEntryKind = leg.kind == .transferOut ? .transferIn : .transferOut
            let legRefs = Set(
                [leg.externalRef, leg.counterpartRef]
                    .map(MovementRules.normaliseReference)
                    .filter { !$0.isEmpty }
            )

            guard !legRefs.isEmpty else {
                continue
            }

            let candidate = legs.first { other in
                guard other.id != leg.id,
                    other.kind == oppositeKind,
                    other.transfer == nil,
                    other.account?.id != leg.account?.id
                else {
                    return false
                }

                let otherRefs = [other.externalRef, other.counterpartRef]
                    .map(MovementRules.normaliseReference)
                return otherRefs.contains { legRefs.contains($0) }
            }

            guard let candidate else {
                continue
            }

            let previous = (leg.status, candidate.status)
            leg.status = .confirmed
            candidate.status = .confirmed

            do {
                _ = try TransferLinker(context: context).link(
                    outLeg: leg.kind == .transferOut ? leg : candidate,
                    inLeg: leg.kind == .transferIn ? leg : candidate
                )
                linked += 1
            } catch {
                leg.status = previous.0
                candidate.status = previous.1
            }
        }

        return linked
    }

    // MARK: - Stages

    private func stop(_ isStopped: @Sendable () -> Bool) -> Bool {
        isStopped() || Task.isCancelled
    }

    private func settlePendingInvestments(now: Date, isStopped: @Sendable () -> Bool) -> Int {
        guard !stop(isStopped) else {
            return 0
        }

        let service = InvestmentService(context: context)
        return (try? service.settlePendingInvestments(now: now)) ?? 0
    }

    private func refreshNotifications(
        promptForNotifications: Bool,
        isStopped: @Sendable () -> Bool
    ) async -> Bool {
        guard !stop(isStopped) else {
            return false
        }

        return await NotificationService(context: context)
            .refresh(promptForPermission: promptForNotifications)
    }

    private func refreshWidget(at now: Date, isStopped: @Sendable () -> Bool) -> Bool {
        guard !stop(isStopped) else {
            return false
        }

        return WidgetSnapshotService(context: context).refresh(at: now) != nil
    }

    /// Advances the diagnostics watermark. Deliberately the last stage: a cancelled run must not
    /// make the UI claim maintenance happened when most of it was skipped.
    private func recordRun(at date: Date, isStopped: @Sendable () -> Bool) {
        guard !stop(isStopped) else {
            return
        }

        guard let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first else {
            return
        }

        // Avoid a CloudKit write on every small save; the diagnostics only need minute detail.
        if let last = settings.lastMaintenanceAt, date.timeIntervalSince(last) < 60 {
            return
        }

        settings.lastMaintenanceAt = date
        try? context.save()
    }
}
