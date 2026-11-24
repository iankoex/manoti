//
//  ManotiApp.swift
//  Manoti
//

import AppServices
import Automation
import NavigationFeature
import SwiftData
import SwiftUI

@main
struct ManotiApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(ManotiAppDelegate.self) private var appDelegate
    #endif

    @State private var root = AppRoot()

    var body: some Scene {
        WindowGroup {
            if let dependencies = root.dependencies {
                ContentView(rulesUpdate: dependencies.rulesUpdateNotice)
                    .environment(dependencies.appService)
                    .environment(dependencies.privacyService)
                    .environment(dependencies.notificationService)
                    .environment(dependencies.accountService)
                    .environment(dependencies.categoryService)
                    .environment(dependencies.ledgerService)
                    .environment(dependencies.transferService)
                    .environment(dependencies.loanService)
                    .environment(dependencies.investmentService)
                    .environment(dependencies.insightsService)
                    .environment(dependencies.budgetService)
                    .environment(dependencies.exchangeRateService)
                    .environment(dependencies.inboxService)
                    .environment(dependencies.parserService)
                    .environment(dependencies.ingestService)
                    .environment(dependencies.ruleService)
                    .environment(dependencies.reconciliationService)
                    .environment(dependencies.exportService)
                    .environment(dependencies.iCloudStatusService)
                    .environment(dependencies.widgetSnapshotService)
                    .environment(dependencies.savingsService)
                    .environment(dependencies.maintenanceService)
                    .modelContainer(dependencies.container)
            } else {
                StartupFailureView(message: root.failureMessage ?? "The local store could not be opened.")
            }
        }
    }
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Manoti could not start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}
