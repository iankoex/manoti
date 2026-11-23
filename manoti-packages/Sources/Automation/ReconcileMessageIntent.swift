//
//  ReconcileMessageIntent.swift
//  Automation
//

import AppIntents
import AppModels
import AppServices
import Foundation
import SwiftData

/// Collects one message for a reconciliation run without writing to the ledger.
///
/// Use inside a Shortcut's `Repeat with Each` over a `Find Messages` result. The action
/// returns `matched`, `possible` or `missing` so the Shortcut can build its own text.
public struct ReconcileMessageIntent: AppIntent {
    public static let title: LocalizedStringResource = "Collect Reconciliation Message"
    public static let description = IntentDescription(
        "Adds one message to a reconciliation run without recording a transaction."
    )

    @Parameter(title: "Message")
    public var text: String

    @Parameter(title: "Sender")
    public var sender: String?

    @Parameter(title: "Received At")
    public var receivedAt: Date?

    @Parameter(title: "Session Token")
    public var sessionToken: String?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Collect \(\.$text)") {
            \.$sender
            \.$receivedAt
            \.$sessionToken
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = await MainActor.run { () -> String in
            guard let container = AppStore.container() else {
                return "error"
            }

            let calendar = Calendar.current
            let anchor = receivedAt ?? Date()
            let start = calendar.startOfDay(for: anchor)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return "error"
            }

            let service = ReconciliationService(context: container.mainContext, calendar: calendar)

            do {
                let message = try service.collect(
                    text: text,
                    sender: sender,
                    receivedAt: receivedAt,
                    token: sessionToken,
                    periodStart: start,
                    periodEnd: end
                )

                let session: ReconcileSession
                if let existing = message.session {
                    session = existing
                } else if let found = try service.session(token: sessionToken) {
                    session = found
                } else {
                    return "missing"
                }

                switch try service.classificationPreview(for: message, in: session) {
                    case .matched:
                        return "matched"
                    case .possible:
                        return "possible"
                    default:
                        return "missing"
                }
            } catch {
                return "error"
            }
        }

        return .result(value: result)
    }
}
