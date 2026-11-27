//
//  SettingsView.swift
//  SettingsFeature
//

import AppIntents
import AppModels
import AppServices
import Modifiers
import ReconcileFeature
import RulesFeature
import SwiftUI
import TagsFeature

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppService.self) private var appService
    @Environment(PrivacyService.self) private var privacyService
    @Environment(NotificationService.self) private var notificationService
    @Environment(ExchangeRateService.self) private var exchangeRates
    @Environment(CategoryService.self) private var categoryService
    @Environment(TagService.self) private var tagService
    @Environment(ReconciliationService.self) private var reconciliationService
    @Environment(ExportService.self) private var exportService
    @Environment(ICloudStatusService.self) private var iCloudStatus
    @Environment(AppMaintenance.self) private var maintenance

    @State private var rateCount = 0
    @State private var categoryCount = 0
    @State private var tagCount = 0
    @State private var reconcileValue = "No sessions yet"
    @State private var lastBackupAt: Date?
    @State private var largeThresholdText = ""
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                moneySection
                investingSection
                messagesSection
                siriSection
                notificationsSection
                backgroundSection
                privacySection
                dataSection
                iCloudSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .onManotiDataChange { reload() }
            .task { await notificationService.refresh() }
            .alert(
                "Could not save",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var moneySection: some View {
        Section {
            NavigationLink {
                DisplayCurrencyView()
            } label: {
                HStack {
                    Label("Display currency", systemImage: "banknote")
                    Spacer()
                    Text(appService.displayCurrency.code)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                ExchangeRatesView()
            } label: {
                HStack {
                    Label("Exchange rates", systemImage: "arrow.left.arrow.right")
                    Spacer()
                    Text(rateCount == 1 ? "1 rate" : "\(rateCount) rates")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                CategoriesView()
            } label: {
                HStack {
                    Label("Categories", systemImage: "square.grid.2x2")
                    Spacer()
                    Text(categoryCount == 1 ? "1 category" : "\(categoryCount) categories")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                TagsView()
            } label: {
                HStack {
                    Label("Tags", systemImage: "tag")
                    Spacer()
                    Text(tagCount == 1 ? "1 tag" : "\(tagCount) tags")
                        .foregroundStyle(.secondary)
                }
            }

            Picker(selection: weekStartsOn) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(weekdayName(weekday)).tag(weekday)
                }
            } label: {
                Label("Week starts on", systemImage: "calendar")
            }
        } header: {
            Text("Money")
        } footer: {
            Text(
                "Other currencies are converted using the newest rate on or before the transaction date. Missing historical rates are shown 1:1 in major units and marked."
            )
        }
    }

    private var investingSection: some View {
        Section {
            Stepper(value: reinvestmentRate, in: 0...3000, step: 25) {
                LabeledContent("Default reinvestment rate") {
                    Text("\(percent(reinvestmentRate.wrappedValue))% gross")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Stepper(value: withholdingTax, in: 0...5000, step: 25) {
                LabeledContent("Default withholding tax") {
                    Text("\(percent(withholdingTax.wrappedValue))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Investments")
        } footer: {
            Text(
                "Used for projections and new investments. Each investment can override the reinvestment rate. Projections are illustrative, not guarantees."
            )
        }
    }

    private var messagesSection: some View {
        Section {
            NavigationLink {
                RulesView()
            } label: {
                Label("Message rules", systemImage: "slider.horizontal.3")
            }

            NavigationLink {
                IngestMemoryListView()
            } label: {
                Label("Learned messages", systemImage: "text.badge.checkmark")
            }

            NavigationLink {
                ReconcileView()
            } label: {
                HStack {
                    Label("Reconcile", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(reconcileValue)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Incoming messages")
        } footer: {
            Text("Bank and mobile money identifiers are managed from each account's detail screen.")
        }
    }

    private var siriSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Shortcuts are ready")
                        .font(.subheadline.weight(.medium))
                    Text("Ask Siri, or find them in Spotlight and the Shortcuts app. Nothing to install.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "mic")
                    .foregroundStyle(.tint)
            }

            #if os(iOS)
            ShortcutsLink()
            #endif
        } header: {
            Text("Siri & Shortcuts")
        } footer: {
            Text(
                "The button opens Manoti's App Shortcuts page in the Shortcuts app, where you can review or add a shortcut. Manoti cannot add shortcuts or Personal Automations for you."
            )
        }
    }

    private var backgroundSection: some View {
        Section("Background updates") {
            LabeledContent("Last maintenance") {
                Text(
                    maintenance.lastRunAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
                )
                .foregroundStyle(.secondary)
            }

            LabeledContent("Waiting messages") {
                Text("\(IngestOutbox().count())")
                    .foregroundStyle(.secondary)
            }

            if let report = maintenance.lastReport {
                LabeledContent("Last replay") {
                    Text(
                        "\(report.outboxDrained) messages · \(report.investmentsSettled) settlements"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Text(
                "iOS decides when background work runs. Shortcut messages are saved first and replayed when Manoti next runs; already-scheduled alerts still fire while the app is closed."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: allowNotifications) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow notifications")
                            .font(.subheadline.weight(.medium))
                        Text("Reminders and alerts appear on this iPhone only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.tint)
                }
            }

            Toggle("Daily reminder", isOn: dailyReminder)
                .disabled(!appService.notificationsEnabled)

            Toggle("Inbox reminder", isOn: inboxReminder)
                .disabled(!appService.notificationsEnabled)

            Toggle("Weekly summary", isOn: weeklySummary)
                .disabled(!appService.notificationsEnabled)

            Toggle("Budget alerts", isOn: budgetAlerts)
                .disabled(!appService.notificationsEnabled)

            Toggle("Large transactions", isOn: largeTransactionAlerts)
                .disabled(!appService.notificationsEnabled)

            LabeledContent {
                HStack(spacing: ManotiSpacing.small) {
                    Text(appService.displayCurrency.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("0", text: $largeThresholdText)
                        .decimalKeyboard()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()

                    Button("Set", action: saveLargeTransactionThreshold)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            } label: {
                Label("Large transaction threshold", systemImage: "arrow.up.right.circle")
            }
            .disabled(!appService.notificationsEnabled || !appService.largeTransactionAlertsEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                Text(
                    "A large transaction alerts at or above this amount in \(appService.displayCurrency.code). Set 0 to turn it off."
                )

                Text("All notifications are scheduled on this iPhone. Manoti does not use a notification server.")

                if appService.privacyModeEnabled {
                    Text("Amounts are omitted from notification text while privacy mode is on.")
                }
            }
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: privacyMode) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy mode")
                            .font(.subheadline.weight(.medium))
                        Text("Hide amounts when opening Manoti.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.tint)
                }
            }

            if appService.privacyModeEnabled {
                Button("Hide amounts now", systemImage: "eye.slash") {
                    privacyService.hide()
                }
            }

            Toggle(isOn: keepRawMessages) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep original message text")
                            .font(.subheadline.weight(.medium))
                        Text("Store the body of new bank and mobile money messages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.tint)
                }
            }

            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private by design")
                        .font(.subheadline.weight(.medium))
                    Text(
                        "Money data stays on this device and in your own iCloud. No account, analytics or third-party service."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.tint)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text(
                "When original message text is off, newly ingested messages store no raw text. Existing entries are unchanged, and the parsed amount, payee and reference are always kept."
            )
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: AppInfo.name)
            LabeledContent("Version", value: version)
        }
    }

    private var allowNotifications: Binding<Bool> {
        Binding(
            get: { appService.notificationsEnabled },
            set: { enabled in
                do {
                    try appService.setNotificationsEnabled(enabled)

                    if enabled {
                        Task { await enableNotifications() }
                    } else {
                        notificationService.cancelAll()
                    }
                } catch {
                    errorMessage = "Could not change notification settings."
                }
            }
        )
    }

    private var dailyReminder: Binding<Bool> {
        Binding(
            get: { appService.dailyReminderEnabled },
            set: { enabled in
                do {
                    try appService.setDailyReminderEnabled(enabled)
                } catch {
                    errorMessage = "Could not change the daily reminder."
                }
            }
        )
    }

    private var inboxReminder: Binding<Bool> {
        Binding(
            get: { appService.inboxReminderEnabled },
            set: { enabled in
                do {
                    try appService.setInboxReminderEnabled(enabled)
                } catch {
                    errorMessage = "Could not change the Inbox reminder."
                }
            }
        )
    }

    private var weeklySummary: Binding<Bool> {
        Binding(
            get: { appService.weeklySummaryEnabled },
            set: { enabled in
                do {
                    try appService.setWeeklySummaryEnabled(enabled)
                } catch {
                    errorMessage = "Could not change the weekly summary."
                }
            }
        )
    }

    private var budgetAlerts: Binding<Bool> {
        Binding(
            get: { appService.budgetAlertsEnabled },
            set: { enabled in
                do {
                    try appService.setBudgetAlertsEnabled(enabled)
                } catch {
                    errorMessage = "Could not change budget alerts."
                }
            }
        )
    }

    private var largeTransactionAlerts: Binding<Bool> {
        Binding(
            get: { appService.largeTransactionAlertsEnabled },
            set: { enabled in
                do {
                    try appService.setLargeTransactionAlertsEnabled(enabled)
                } catch {
                    errorMessage = "Could not change large transaction alerts."
                }
            }
        )
    }

    private var thresholdText: String {
        let money = Money(
            minorUnits: appService.largeTransactionThresholdMinor,
            currency: appService.displayCurrency
        )
        return "\(money.decimalValue)"
    }

    private func enableNotifications() async {
        let granted = await notificationService.requestAuthorization()

        guard granted else {
            try? appService.setNotificationsEnabled(false)
            errorMessage = "Notifications are not allowed for Manoti. Turn them on in iOS Settings."
            return
        }

        await notificationService.refresh()
    }

    private func saveLargeTransactionThreshold() {
        let trimmed = largeThresholdText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            applyLargeTransactionThreshold(0)
            return
        }

        guard let parsed = MoneyParser.parse(trimmed, defaultCurrency: appService.displayCurrency)?.money,
            parsed.minorUnits >= 0
        else {
            largeThresholdText = thresholdText
            errorMessage = "Enter a valid threshold in \(appService.displayCurrency.code)."
            return
        }

        applyLargeTransactionThreshold(parsed.minorUnits)
    }

    private func applyLargeTransactionThreshold(_ minorUnits: Int64) {
        do {
            try appService.setLargeTransactionThresholdMinor(minorUnits)
            largeThresholdText = thresholdText
        } catch {
            errorMessage = "Could not save the large transaction threshold."
        }
    }

    private var privacyMode: Binding<Bool> {
        Binding(
            get: { appService.privacyModeEnabled },
            set: { enabled in
                do {
                    try appService.setPrivacyModeEnabled(enabled)

                    if enabled {
                        privacyService.hide()
                    } else {
                        privacyService.reveal()
                    }
                } catch {
                    errorMessage = "Could not change privacy mode."
                }
            }
        )
    }

    private var keepRawMessages: Binding<Bool> {
        Binding(
            get: { appService.keepRawMessages },
            set: { keep in
                do {
                    try appService.setKeepRawMessages(keep)
                } catch {
                    errorMessage = "Could not change message retention."
                }
            }
        )
    }

    private var weekStartsOn: Binding<Int> {
        Binding(
            get: { appService.weekStartsOn },
            set: { weekday in
                do {
                    try appService.setWeekStartsOn(weekday)
                } catch {
                    errorMessage = "Choose a valid weekday."
                }
            }
        )
    }

    private var reinvestmentRate: Binding<Int> {
        Binding(
            get: { appService.reinvestmentRateBasisPoints },
            set: { basisPoints in
                do {
                    try appService.setReinvestmentRateBasisPoints(basisPoints)
                } catch {
                    errorMessage = "Choose a reinvestment rate between 0% and 30%."
                }
            }
        )
    }

    private var withholdingTax: Binding<Int> {
        Binding(
            get: { appService.withholdingTaxBasisPoints },
            set: { basisPoints in
                do {
                    try appService.setWithholdingTaxBasisPoints(basisPoints)
                } catch {
                    errorMessage = "Choose a withholding tax between 0% and 50%."
                }
            }
        )
    }

    private func percent(_ basisPoints: Int) -> String {
        "\(Decimal(basisPoints) / 100)"
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard (1...symbols.count).contains(weekday) else {
            return "—"
        }

        return symbols[weekday - 1]
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                ExportBackupView()
            } label: {
                HStack {
                    Label("Export & backup", systemImage: "externaldrive")
                    Spacer()
                    Text(lastBackupText)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Data")
        } footer: {
            Text("JSON backup and CSV export. Restoring merges by ID and never deletes existing rows.")
        }
    }

    private var lastBackupText: String {
        guard let lastBackupAt else {
            return "Never"
        }

        return lastBackupAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var iCloudSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: ManotiSpacing.small) {
                    if iCloudStatus.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(iCloudStatus.status.displayName)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("Account status", systemImage: "icloud")
            }

            if let detail = iCloudStatus.status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Check iCloud") {
                Task { await iCloudStatus.refresh() }
            }
            .disabled(iCloudStatus.isChecking)
        } header: {
            Text("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: ManotiSpacing.small) {
                Text(
                    "Sync is managed by the system. Manoti cannot show a pending-change count or an exact last-successful-sync time."
                )

                if iCloudStatus.status == .noAccount {
                    Text("Sign in to iCloud in the Settings app to use iCloud sync.")
                }
            }
        }
        .task {
            if iCloudStatus.status == .unknown {
                await iCloudStatus.refresh()
            }
        }
    }

    private func reload() {
        rateCount = (try? exchangeRates.latestRates())?.count ?? 0
        categoryCount = (try? categoryService.fetchCategories())?.count ?? 0
        tagCount = (try? tagService.fetchTags(includeClosed: true))?.count ?? 0
        reconcileValue = latestSessionValue()
        lastBackupAt = exportService.lastBackupAt()
        largeThresholdText = thresholdText
    }

    private func latestSessionValue() -> String {
        do {
            guard let session = try reconciliationService.latestSession() else {
                return "No sessions yet"
            }

            return ReconcileFormatting.settingsValue(for: session)
        } catch {
            return "No sessions yet"
        }
    }
}
