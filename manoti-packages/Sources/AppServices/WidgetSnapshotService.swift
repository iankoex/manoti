//
//  WidgetSnapshotService.swift
//  AppServices
//

import AppModels
import AppPackageExtensions
import Foundation
import Observation
import SwiftData

#if canImport(WidgetKit)
import WidgetKit
#endif

/// A tiny read-only summary the home-screen widget can display without opening the store.
///
/// The app group already contains the SwiftData store, but a widget does not need the whole
/// schema. Writing a small JSON snapshot keeps the extension free of package dependencies
/// and avoids querying the database from the widget process.
nonisolated public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let monthSpendText: String
    public let safeToSpendText: String
    public let isPrivacyModeEnabled: Bool

    public init(
        updatedAt: Date,
        monthSpendText: String,
        safeToSpendText: String,
        isPrivacyModeEnabled: Bool
    ) {
        self.updatedAt = updatedAt
        self.monthSpendText = monthSpendText
        self.safeToSpendText = safeToSpendText
        self.isPrivacyModeEnabled = isPrivacyModeEnabled
    }
}

/// Builds and writes the widget snapshot into the shared app group.
@Observable
nonisolated public final class WidgetSnapshotService: Loggable {
    public static let appGroupIdentifier = "group.com.iankoex.manoti"
    public static let filename = "widget-snapshot.json"

    private let context: ModelContext
    private let accounts: AccountService
    private let insights: InsightsService
    private let budget: BudgetService
    private let appService: AppService

    public init(context: ModelContext) {
        self.context = context
        self.accounts = AccountService(context: context)
        self.insights = InsightsService(context: context)
        self.budget = BudgetService(context: context)
        self.appService = AppService(context: context)
    }

    /// Builds the current snapshot even when the app group is unavailable (tests, macOS).
    public func makeSnapshot(at now: Date = Date()) throws -> WidgetSnapshot {
        appService.reload()
        let calendar = Calendar.current
        let displayCurrency = appService.displayCurrency
        let hidden = appService.privacyModeEnabled
        let month = BudgetPeriodKind.month.dateInterval(containing: now, calendar: calendar)
        let monthSpend = try insights.total(
            kind: .expense,
            from: month.start,
            to: month.end,
            displayCurrency: displayCurrency
        )

        let safeToSpend = try safeToSpend(at: now, calendar: calendar, displayCurrency: displayCurrency)

        return WidgetSnapshot(
            updatedAt: now,
            monthSpendText: text(monthSpend.amount, hidden: hidden),
            safeToSpendText: safeToSpend.map { text($0, hidden: hidden) } ?? "—",
            isPrivacyModeEnabled: hidden
        )
    }

    /// Writes the snapshot and asks WidgetKit to refresh. Safe to call on every data change.
    @discardableResult
    public func refresh(at now: Date = Date()) -> WidgetSnapshot? {
        let snapshot: WidgetSnapshot

        do {
            snapshot = try makeSnapshot(at: now)
        } catch {
            log("Widget snapshot failed: \(error.localizedDescription)", level: .error)
            // Privacy is a security override: never leave an older unmasked file behind.
            if appService.privacyModeEnabled {
                let masked = WidgetSnapshot(
                    updatedAt: now,
                    monthSpendText: Self.AmountMaskPlaceholder,
                    safeToSpendText: Self.AmountMaskPlaceholder,
                    isPrivacyModeEnabled: true
                )
                try? write(masked)
            }
            return nil
        }

        do {
            try write(snapshot)
        } catch {
            log("Widget snapshot write failed: \(error.localizedDescription)", level: .error)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return snapshot
    }

    /// Read back what the widget will see. Used by tests and diagnostics.
    public func storedSnapshot() -> WidgetSnapshot? {
        guard let url = Self.snapshotURL(), let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? Self.decoder().decode(WidgetSnapshot.self, from: data)
    }

    private func safeToSpend(
        at now: Date,
        calendar: Calendar,
        displayCurrency: Currency
    ) throws -> Money? {
        guard
            let period = try? budget.currentPeriodIfExists(
                kind: .month,
                containing: now,
                calendar: calendar
            )
        else {
            return nil
        }

        let envelopes = try budget.envelopes(for: period)
        guard !envelopes.isEmpty else {
            return nil
        }

        return try budget.safeToSpend(for: period, displayCurrency: displayCurrency, now: now).amount
    }

    private static let AmountMaskPlaceholder = "••••"

    private func text(_ money: Money, hidden: Bool) -> String {
        hidden ? Self.AmountMaskPlaceholder : money.formatted()
    }

    private func write(_ snapshot: WidgetSnapshot) throws {
        guard let url = Self.snapshotURL() else {
            return
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.encoder().encode(snapshot).write(to: url, options: .atomic)
    }

    public static func snapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
