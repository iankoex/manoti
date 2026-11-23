//
//  LogExpenseIntent.swift
//  Automation
//

import AppIntents
import AppModels
import AppPackageExtensions
import AppServices
import Foundation
import SwiftData

/// Records a payment from text.
///
/// The parameter is the message itself, so a Shortcut can pass a whole bank alert, and Siri can
/// be given a spoken phrase such as "paid 250 for fuel". Nothing has to be split into fields.
public struct LogExpenseIntent: AppIntent {
    /// Keep in sync with the account picker in `AddEntryView`.
    static let lastAccountIDKey = "manoti.lastAccountID"

    public static let title: LocalizedStringResource = "Log Payment"
    public static let description = IntentDescription(
        "Records a payment from its message text, without opening the app."
    )

    @Parameter(
        title: "Message",
        description: "The payment message, or a phrase such as Paid 250 for fuel."
    )
    public var message: String

    @Parameter(title: "Merchant")
    public var merchant: String?

    @Parameter(title: "Account")
    public var accountName: String?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message)") {
            \.$merchant
            \.$accountName
        }
    }

    public static let supportedModes: IntentModes = [.background]

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var maintenanceContext: ModelContext?

        let summary: String = {
            guard let container = AppStore.container() else {
                return "Manoti could not open its store."
            }

            let context = container.mainContext
            maintenanceContext = context

            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return "Give me the payment message."
            }

            let privacy = AppService(context: context).privacyModeEnabled

            // A bank or mobile money alert carries its own amount, payee and date. Probe the
            // parser first: running the full ingester on spoken text would park a spurious
            // "could not read" message before the spoken-payment fallback records it.
            let parser = ParserService(context: context)
            if let parsed = try? parser.parse(text: text, sender: nil, receivedAt: Date()),
                case .parsed = parsed,
                let outcome = try? IngestService(context: context).ingest(
                    text: text,
                    sender: nil,
                    receivedAt: Date()
                )
            {
                return privacy ? "Message handled. Open Manoti to review it." : outcome.summary
            }

            // Otherwise read a spoken payment: an amount plus a word such as paid or for fuel.
            guard let spoken = SpokenPayment.read(text) else {
                return "Manoti could not read a payment in that message."
            }

            let accountService = AccountService(context: context)
            let accounts = (try? accountService.fetchAccounts()) ?? []

            guard !accounts.isEmpty else {
                return "Add an account in Manoti first."
            }

            let account: Account
            if let accountName, !accountName.isEmpty {
                guard let match = accounts.first(where: { matches($0, name: accountName) }) else {
                    return "No account named \(accountName). Open Manoti to check the account names."
                }

                account = match
            } else if let lastUsed = lastUsedAccount(in: accounts) {
                account = lastUsed
            } else if accounts.count == 1, let only = accounts.first {
                account = only
            } else {
                return "Several accounts are set up. Open Manoti and choose one, or name the account."
            }

            guard spoken.money.minorUnits > 0 else {
                return "Enter an amount greater than zero."
            }

            let payee = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? spoken.payee

            do {
                let entry = try LedgerService(context: context).record(
                    kind: .expense,
                    amountMinor: spoken.money.minorUnits,
                    account: account,
                    payee: payee,
                    note: ""
                )

                // Remember the account for the next request, matching the Add screen.
                UserDefaults.standard.set(account.id.uuidString, forKey: Self.lastAccountIDKey)

                return
                    "Recorded \(SpokenAmount.describe(entry.amount, hidden: privacy)) in \(account.displayName)."
            } catch {
                return "Manoti could not save this expense: \(error.localizedDescription)"
            }
        }()

        if let maintenanceContext {
            await AppMaintenance(context: maintenanceContext).runAfterWrite(promptForNotifications: false)
        }

        // The dialog makes Shortcuts and Siri say the outcome; the value stays for flows that consume it.
        return .result(value: summary, dialog: "\(summary)")
    }

    /// Chooses the last account used in the app.
    ///
    /// An explicit name wins, then the last account used, then the only account. Several candidates with
    /// no hint are reported instead of picked at random.
    private func lastUsedAccount(in accounts: [Account]) -> Account? {
        guard let storedID = UserDefaults.standard.string(forKey: Self.lastAccountIDKey) else {
            return nil
        }

        return accounts.first { $0.id.uuidString == storedID }
    }

    private func matches(_ account: Account, name: String) -> Bool {
        account.name.caseInsensitiveCompare(name) == .orderedSame
            || account.displayName.caseInsensitiveCompare(name) == .orderedSame
    }
}

/// Reads a short spoken payment such as "paid 250 for fuel".
nonisolated enum SpokenPayment {
    static func read(_ text: String) -> (money: Money, payee: String)? {
        guard let parsed = MoneyParser.parse(text) else {
            return nil
        }

        // A bare number is only trusted when the words around it say something was paid.
        if !parsed.hadCurrencyToken {
            let pattern = #"\b(PAID|PAY|SPENT|SPEND|BOUGHT|BUY|FOR)\b"#
            guard text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                return nil
            }
        }

        var payee = text
        payee = payee.replacingOccurrences(
            of: #"(?i)\b(kshs?|kes|usd|eur|gbp|ugx|tzs|rwf|zar)\b"#,
            with: " ",
            options: .regularExpression
        )
        payee = payee.replacingOccurrences(
            of: #"[0-9][0-9.,]*"#,
            with: " ",
            options: .regularExpression
        )
        payee = payee.replacingOccurrences(
            of: #"(?i)\b(paid|pay|spent|spend|bought|buy|for|on|at|to)\b"#,
            with: " ",
            options: .regularExpression
        )
        payee = payee.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        payee = payee.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        return (parsed.money, payee)
    }
}
