//
//  AppShortcutsTests.swift
//  ManotiTests
//

import AppIntents
import AppPackageExtensions
import Foundation
import Testing

@testable import AppModels
@testable import Automation

@MainActor
@Suite("App Shortcuts")
struct AppShortcutsTests {
    @Test("The app-target shortcut provider stays within the ten-shortcut limit")
    func shortcutLimit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Manoti/ManotiAppTargetShortcuts.swift"),
            encoding: .utf8
        )

        let count = source.components(separatedBy: "AppShortcut(").count - 1
        #expect(count > 0)
        #expect(count <= 10)
    }

    @Test("Open Inbox runs in the foreground and leaves a route")
    func openInboxRoute() {
        #expect(OpenInboxIntent.supportedModes.contains(.foreground))
        #expect(OpenInboxIntent.pendingRouteKey == "manoti.pendingRoute")
        #expect(OpenInboxIntent.inboxRoute == "inbox")
    }

    @Test("Review Reconciliation runs in the foreground and leaves a route")
    func openReconcileRoute() {
        #expect(OpenReconcileIntent.supportedModes.contains(.foreground))
        #expect(OpenReconcileIntent.pendingRouteKey == "manoti.pendingRoute")
        #expect(OpenReconcileIntent.reconcileRoute == "reconcile")
    }

    @Test("Log Payment and Mark Ride return a value and a spoken dialog")
    func dialogResults() {
        expectDialogWithValue(LogExpenseIntent.PerformResult.self)
        expectDialogWithValue(MarkContextIntent.PerformResult.self)

        let logged: IntentResultContainer<String, Never, Never, IntentDialog> = .result(
            value: "Recorded KES 1.00 in M-Pesa.",
            dialog: "Recorded KES 1.00 in M-Pesa."
        )
        #expect(logged.value == "Recorded KES 1.00 in M-Pesa.")
        #expect(logged.dialog != nil)
    }

    @Test("A spoken amount is redacted when privacy is on")
    func spokenAmountPrivacy() {
        let money = Money(minorUnits: 1_000, currency: CurrencyCatalog.currency(for: "KES"))

        #expect(SpokenAmount.describe(money, hidden: true) == "an amount")
        #expect(SpokenAmount.describe(money, hidden: false).contains("10.00"))
    }

    @Test("A spoken payment reads an amount and a payee")
    func spokenPayment() {
        let read = SpokenPayment.read("Paid 250 for fuel")

        #expect(read?.money.minorUnits == 25_000)
        #expect(read?.payee == "fuel")
    }

    @Test("A bare number without a payment word is not a payment")
    func spokenPaymentNeedsVerb() {
        #expect(SpokenPayment.read("Call 0722000111") == nil)
    }

    @Test("A currency token is enough to read a payment")
    func spokenPaymentCurrency() {
        let read = SpokenPayment.read("KES 1,200 lunch")

        #expect(read?.money.minorUnits == 120_000)
        #expect(read?.payee == "lunch")
    }

    @Test("A batch splits on lines and drops blank lines")
    func batchSplit() {
        let blob = """
            UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Petrol Station. on 21/11/26 at 11:54 AM.

            UKJME2X5ZR Confirmed.You have received Ksh100.00 from BRENDAH on 19/11/26 at 3:07 PM
            """

        let parts = CollectPaymentMessagesIntent.split(blob)

        #expect(parts.count == 2)
        #expect(parts[0].hasPrefix("UKL6H2AF65"))
        #expect(parts[1].hasPrefix("UKJME2X5ZR"))
    }

    @Test("A single pasted message stays one message")
    func batchSplitSingle() {
        let parts = CollectPaymentMessagesIntent.split("  KES 10.00 paid to Kiosk.  ")

        #expect(parts == ["KES 10.00 paid to Kiosk."])
    }

    @Test("Empty clipboard text collects nothing")
    func batchSplitEmpty() {
        #expect(CollectPaymentMessagesIntent.split("   \n\n  ").isEmpty)
    }

    private func expectDialogWithValue<Result>(_: Result.Type) where Result: ProvidesDialog & ReturnsValue<String> {}
}
