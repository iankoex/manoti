//
//  IngestBankMessageIntent.swift
//  Automation
//

import AppIntents
import AppModels
import AppServices
import Foundation
import SwiftData

public struct IngestBankMessageIntent: AppIntent {
    public static let title: LocalizedStringResource = "Collect Payment Message"
    public static let description = IntentDescription(
        "Collects one bank or mobile money message and records it, or files it for review."
    )

    /// The write is complete without the UI, so it can run while Manoti is suspended.
    public static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Message")
    public var text: String

    @Parameter(title: "Sender")
    public var sender: String?

    @Parameter(title: "Received at")
    public var receivedAt: Date?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Collect \(\.$text)") {
            \.$sender
            \.$receivedAt
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let stamp = receivedAt ?? Date()
        let receipt = OutboxMessage(
            text: text,
            sender: sender,
            receivedAt: stamp,
            dedupeHash: IngestService.dedupeHash(sender: sender, text: text)
        )
        let outbox = IngestOutbox()
        try? outbox.enqueue(receipt)

        guard let container = AppStore.container() else {
            return .result(value: "Saved this message. Open Manoti once to record it.")
        }

        let context = container.mainContext

        do {
            let outcome = try IngestService(context: context).ingest(
                text: text,
                sender: sender,
                receivedAt: stamp
            )
            try? outbox.remove(receipt)
            await AppMaintenance(context: context).runAfterWrite(promptForNotifications: false)

            return .result(value: outcome.summary)
        } catch {
            // The outbox keeps the message for the next launch or intent.
            return .result(value: "Saved this message. Manoti will record it next time it runs.")
        }
    }
}
