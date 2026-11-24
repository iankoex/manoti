//
//  AppRoot.swift
//  Manoti
//

import AppModels
import AppServices
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

/// Composition root: builds the model container and the services the app runs on.
@MainActor
final class AppRoot {
    struct Dependencies {
        let container: ModelContainer
        let appService: AppService
        let privacyService: PrivacyService
        let notificationService: NotificationService
        let accountService: AccountService
        let categoryService: CategoryService
        let ledgerService: LedgerService
        let transferService: TransferService
        let loanService: LoanService
        let investmentService: InvestmentService
        let insightsService: InsightsService
        let budgetService: BudgetService
        let exchangeRateService: ExchangeRateService
        let inboxService: InboxService
        let parserService: ParserService
        let ingestService: IngestService
        let ruleService: RuleService
        let exportService: ExportService
        let widgetSnapshotService: WidgetSnapshotService
        let savingsService: SavingsService
        let reconciliationService: ReconciliationService
        let iCloudStatusService: ICloudStatusService
        let maintenanceService: AppMaintenance
        /// Set once when an app update advanced the bundled message rules.
        let rulesUpdateNotice: SharedRulesUpdate?
    }

    private static let logger = Logger(subsystem: "com.iankoex.manoti", category: "AppRoot")

    let dependencies: Dependencies?
    let failureMessage: String?

    init() {
        guard let container = AppStore.container() else {
            dependencies = nil
            failureMessage = "The local store could not be opened."
            return
        }

        let context = container.mainContext

        let appService = AppService(context: context)

        do {
            try SeedService(context: context).seedIfNeeded()
        } catch {
            Self.logger.error("Seeding failed: \(error.localizedDescription, privacy: .public)")
        }

        // Rule fixes ship with the app; apply them without waiting for a manual update.
        var rulesUpdateNotice: SharedRulesUpdate?

        do {
            if let update = try SharedRulesService(context: context).installBundledRulesIfNeeded(),
                update.shouldNotify
            {
                rulesUpdateNotice = update
            }
        } catch {
            Self.logger.error(
                "Shared rules could not be installed: \(error.localizedDescription, privacy: .public)"
            )
        }

        appService.reload()

        // Replay anything a Shortcut parked while the app was unavailable.
        let maintenanceService = AppMaintenance(context: context)
        _ = maintenanceService.drainAtLaunch()
        AppBackgroundScheduler.register(container: container)
        Task { await AppBackgroundScheduler.schedule() }

        let investmentService = InvestmentService(context: context)
        do {
            try investmentService.settlePendingInvestments()
        } catch {
            Self.logger.error("Investment settlement failed: \(error.localizedDescription, privacy: .public)")
        }

        // Set before the scene becomes active so foreground alerts are not dropped.
        UNUserNotificationCenter.current().delegate = ManotiNotificationDelegate.shared

        dependencies = Dependencies(
            container: container,
            appService: appService,
            privacyService: PrivacyService(
                appService: appService,
                clearNotifications: PrivacyService.clearSystemNotifications
            ),
            notificationService: NotificationService(context: context),
            accountService: AccountService(context: context),
            categoryService: CategoryService(context: context),
            ledgerService: LedgerService(context: context),
            transferService: TransferService(context: context),
            loanService: LoanService(context: context),
            investmentService: investmentService,
            insightsService: InsightsService(context: context),
            budgetService: BudgetService(context: context),
            exchangeRateService: ExchangeRateService(context: context),
            inboxService: InboxService(context: context),
            parserService: ParserService(context: context),
            ingestService: IngestService(context: context),
            ruleService: RuleService(context: context),
            exportService: ExportService(context: context),
            widgetSnapshotService: WidgetSnapshotService(context: context),
            savingsService: SavingsService(context: context),
            reconciliationService: ReconciliationService(context: context),
            iCloudStatusService: ICloudStatusService(),
            maintenanceService: maintenanceService,
            rulesUpdateNotice: rulesUpdateNotice
        )
        failureMessage = nil
    }
}
