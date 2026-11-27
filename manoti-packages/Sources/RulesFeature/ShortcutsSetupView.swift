//
//  ShortcutsSetupView.swift
//  RulesFeature
//

import AppIntents
import Automation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ShortcutsSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isTesting = false
    @State private var didCopyTestMessage = false

    private let testMessage =
        "UKL6H2AF65 Confirmed. Ksh1,510.00 paid to Petrol Station. on 21/11/26 at 11:54 AM."
        + " New mobile money balance is Ksh939.68. Transaction cost, Ksh8.30."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Ask Siri, or use the Shortcuts app")
                        .font(.title3.weight(.semibold))

                    Text(
                        "Manoti's App Shortcuts are already available in Siri, Spotlight and the Shortcuts app. There is nothing to install or turn on."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text(
                        "iOS 27 opens a new shortcut on “Describe a Shortcut”. Tap Edit in the top right to switch to the manual editor; the action list is already at the bottom, so there is no Add Action button."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    #if os(iOS)
                    ShortcutsLink()
                    SiriTipView(intent: LogExpenseIntent())
                    #endif

                    Divider()

                    Text("Which action to use")
                        .font(.title3.weight(.semibold))

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Automation or Shortcut → Collect Payment Message", systemImage: "gearshape.2")
                        Label("A whole day at once → Collect Payment Messages", systemImage: "tray.full")
                        Label("Siri or one-off → Log Payment", systemImage: "mic")
                    }
                    .font(.subheadline)

                    Text(
                        "Collect actions are for messages that arrive on their own. Log Payment takes the same message text, so you can paste it or say it: “Log 250 for fuel”. Only the message is a field; there is nothing to split up."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Divider()

                    Text("Automatic bank messages")
                        .font(.title3.weight(.semibold))

                    Text(
                        "iOS does not let any app read SMS by itself, and Manoti cannot create this automation for you. Create it once, yourself, in the Shortcuts app; after that it runs on every matching message."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Step(
                        number: 1,
                        title: "Create the automation",
                        detail:
                            "Shortcuts → Library → Automation (on iOS 26, use the Automation tab instead). Tap the floating + New Shortcut at the bottom. On “Describe a Shortcut”, tap Edit in the top right, then choose Automation → Message from the action list. There is no + on the Automation screen itself."
                    )
                    Step(
                        number: 2,
                        title: "Type the sender and a content filter",
                        detail:
                            "In the Message trigger, tap Sender and type the alphanumeric sender ID exactly (for example BANKID), then press Return. You do not need a contact. Tap Add Filter: the default condition is Sender is. Tap Sender and switch it to Message, set the operator to contains, then enter a phrase every alert includes."
                    )
                    Step(
                        number: 3,
                        title: "Keep it automatic",
                        detail:
                            "Leave the automation enabled. Keep Confirm Before Running off; long-press the automation to change it."
                    )
                    Step(
                        number: 4,
                        title: "Add the Manoti action",
                        detail:
                            "In the same editor, search Manoti in the action list at the bottom. There is no Add Action button on iOS 27. Choose Collect Payment Message, set Message to Shortcut Input and type the same sender ID into Sender. Leave Received at empty unless the shortcut can read the message date; Manoti uses the date inside the message when there is one."
                    )
                    Step(
                        number: 5,
                        title: "Test it",
                        detail:
                            "Send yourself a message from that sender, then open Manoti → Inbox. The entry should be waiting."
                    )

                    Text(
                        "A bank receipt for a payment may name neither M-PESA nor KES. Add the bank's sender, or a phrase every receipt contains such as “has been received”, so the receipt reaches Manoti and can name the merchant."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("Collect the whole day in one run")
                        .font(.headline)

                    Text(
                        "Run once at 8pm instead of on every message. No Repeat step, and no message list to wire up: Shortcuts hands the messages over as text."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Step(
                        number: 1,
                        title: "Create a Time of Day automation",
                        detail:
                            "Shortcuts → Library → + New Shortcut → Edit in the top right → Automation → Time of Day → 8:00 PM. On iOS 26 the Automation tab has its own +."
                    )
                    Step(
                        number: 2,
                        title: "Find today’s messages",
                        detail:
                            "Search Find Message in the action list. Set Date to today and Body contains mpesa or the name of your bank. Add a Read is true filter if you only want messages you have opened."
                    )
                    Step(
                        number: 3,
                        title: "Copy them",
                        detail:
                            "Search Copy to Clipboard and leave its input as the Find Message result."
                    )
                    Step(
                        number: 4,
                        title: "Collect them at once",
                        detail:
                            "Search Get Clipboard, then search Manoti → Collect Payment Messages and set Messages to the Clipboard value. Leave Sender empty. Received At is only a fallback — each message keeps its own date and time when it has one."
                    )
                    Step(
                        number: 5,
                        title: "Review anything unread",
                        detail:
                            "Messages Manoti cannot parse wait in the Inbox. The action reports how many were recorded, already recorded, need review or unread."
                    )

                    Divider()

                    Text("Senders that are not in Contacts")
                        .font(.headline)

                    Text(
                        "Banks often send from an alphanumeric ID like BANKID. iOS cannot add that to Contacts, but the Sender field accepts typed text. Type the ID directly and add a Message contains filter; do not try to pick a contact."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Step(
                        number: 1,
                        title: "Add the sender ID to the account",
                        detail:
                            "Manoti → Accounts → open the account → Message identifiers → + → Add identifier → Type: Sender name → Value: type the exact sender ID."
                    )
                    Step(
                        number: 2,
                        title: "Use the same literal in the shortcut",
                        detail:
                            "The shortcut cannot read the sender from the trigger, so type the same sender ID into Manoti’s Sender field. The Message contains filter decides when the automation runs."
                    )

                    Divider()

                    Text("Daily reconciliation (optional)")
                        .font(.title3.weight(.semibold))

                    Text(
                        "This does not log new payments. It compares a day of messages with the ledger and reports what is missing on either side. Importing or ignoring stays a manual choice in Manoti."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Step(
                        number: 1,
                        title: "Create a shortcut",
                        detail:
                            "Shortcuts → + New Shortcut → Edit in the top right. Then search Find Message in the action list."
                    )
                    Step(
                        number: 2,
                        title: "Choose the messages",
                        detail:
                            "Set Date to the last 1 day. Use Add Filter → Body contains a phrase from the alerts; Sender is optional and not required for an alphanumeric ID."
                    )
                    Step(
                        number: 3,
                        title: "Repeat over them",
                        detail: "Add Repeat with Each and set Repeat with Each to the found messages."
                    )
                    Step(
                        number: 4,
                        title: "Collect each message",
                        detail:
                            "Inside the repeat: search Manoti → Collect Reconciliation Message. Set Message to Repeat Item, Sender to Sender, Received At to Date, and Session Token to the word daily."
                    )
                    Step(
                        number: 5,
                        title: "Finish the run",
                        detail:
                            "After the repeat: search Manoti → Finish Reconciliation. Use the same Session Token (daily). It returns a line such as 18 messages · 15 matched · 2 missing from app · 1 not in messages."
                    )
                    Step(
                        number: 6,
                        title: "Review it",
                        detail:
                            "Open Manoti → Settings → Reconcile to import missing messages or ignore ledger rows. Nothing is ever deleted automatically."
                    )

                    Text(
                        "The summary line contains counts only, never amounts. The same token safely starts a fresh session on each run."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Divider()

                    Text("Test before you wait")
                        .font(.headline)

                    Text("A realistic message to paste into Test a message:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(testMessage)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    #if canImport(UIKit)
                    Button {
                        copyTestMessage()
                    } label: {
                        Label(didCopyTestMessage ? "Copied" : "Copy test message", systemImage: copySymbol)
                    }
                    .buttonStyle(.bordered)
                    #endif

                    Button("Test a message", systemImage: "text.bubble") {
                        isTesting = true
                    }
                    .buttonStyle(.borderedProminent)

                    Text(
                        "If the message does not parse, edit the rule in Message rules instead of waiting for the automation to fail."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Shortcuts setup")
            .navigationBarTitleDisplayModeInlineCompat()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .sheet(isPresented: $isTesting) {
                RulePlaygroundView()
            }
        }
    }

    private var copySymbol: String {
        didCopyTestMessage ? "checkmark" : "doc.on.doc"
    }

    private func copyTestMessage() {
        #if canImport(UIKit)
        UIPasteboard.general.string = testMessage
        didCopyTestMessage = true
        #endif
    }
}

private struct Step: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func navigationBarTitleDisplayModeInlineCompat() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
