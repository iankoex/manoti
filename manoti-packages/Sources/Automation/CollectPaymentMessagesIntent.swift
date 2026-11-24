//
//  CollectPaymentMessagesIntent.swift
//  Automation
//

import AppIntents
import AppModels
import AppServices
import Foundation
import SwiftData

/// Collects a day of bank or mobile money messages in one action.
///
/// The parameter is plain text rather than a message list because Shortcuts will not reliably
/// hand a `Find Message` result to an app intent. Text accepts the result directly, a clipboard
/// value, or a pasted blob; `split` turns that blob back into individual messages.
public struct CollectPaymentMessagesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Collect Payment Messages"
    public static let description = IntentDescription(
        "Collects bank or mobile money message text and records the ones Manoti can read."
    )

    @Parameter(
        title: "Messages",
        description: "Message text. One message per line, or a clipboard value."
    )
    public var messages: String

    @Parameter(title: "Sender")
    public var sender: String?

    @Parameter(title: "Received At")
    public var receivedAt: Date?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Collect \(\.$messages)") {
            \.$sender
            \.$receivedAt
        }
    }

    public static let supportedModes: IntentModes = [.background]

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let chunks = Self.split(messages)
        guard !chunks.isEmpty else {
            let summary = "No payment messages to collect."
            return .result(value: summary, dialog: "\(summary)")
        }

        let stamp = receivedAt ?? Date()
        let outbox = IngestOutbox()
        var receipts: [OutboxMessage] = []

        // Park every line before doing any work, so a timeout mid-batch loses nothing.
        for chunk in chunks {
            let receipt = OutboxMessage(
                text: chunk,
                sender: sender,
                receivedAt: stamp,
                dedupeHash: IngestService.dedupeHash(sender: sender, text: chunk)
            )
            try? outbox.enqueue(receipt)
            receipts.append(receipt)
        }

        guard let container = AppStore.container() else {
            let summary = "Saved \(chunks.count) messages. Open Manoti once to record them."
            return .result(value: summary, dialog: "\(summary)")
        }

        let context = container.mainContext
        let parser = ParserService(context: context)
        let ingest = IngestService(context: context)

        var tally = Tally()
        var index = 0

        while index < chunks.count {
            var text = chunks[index]
            var consumed = 1

            if !Self.reads(text, parser: parser, sender: sender, at: stamp) {
                // A wrapped message is two lines that only read as one message together.
                // Only join lines that are also unreadable alone, so a good message is
                // never swallowed by the noise above it.
                var joined = text
                var lookahead = 1

                while lookahead <= 2, index + lookahead < chunks.count {
                    let next = chunks[index + lookahead]
                    guard !Self.reads(next, parser: parser, sender: sender, at: stamp) else {
                        break
                    }

                    joined += " " + next
                    lookahead += 1

                    if Self.reads(joined, parser: parser, sender: sender, at: stamp) {
                        text = joined
                        consumed = lookahead
                        break
                    }
                }
            }

            do {
                let outcome = try ingest.ingest(text: text, sender: sender, receivedAt: stamp)
                tally.add(outcome.status)
                for offset in 0..<consumed {
                    try? outbox.remove(receipts[index + offset])
                }
            } catch {
                tally.unread += 1
                // Leave the receipts in place for the next run.
            }

            index += consumed
        }

        await AppMaintenance(context: context).runAfterWrite(promptForNotifications: false)

        let summary = tally.summary
        return .result(value: summary, dialog: "\(summary)")
    }

    /// Separates a blob of message text into one candidate per line.
    ///
    /// Blank lines are dropped. Wrapped messages are rejoined later, once the parser can say
    /// whether two lines read better together than apart.
    static func split(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    private static func reads(
        _ text: String,
        parser: ParserService,
        sender: String?,
        at date: Date
    ) -> Bool {
        guard let outcome = try? parser.parse(text: text, sender: sender, receivedAt: date) else {
            return false
        }

        if case .parsed = outcome {
            return true
        }

        return false
    }

    private struct Tally {
        var recorded = 0
        var needsReview = 0
        var duplicate = 0
        var ignored = 0
        var unread = 0

        var total: Int {
            recorded + needsReview + duplicate + ignored + unread
        }

        mutating func add(_ status: IngestOutcome.Status) {
            switch status {
                case .recorded:
                    recorded += 1
                case .needsReview:
                    needsReview += 1
                case .duplicate:
                    duplicate += 1
                case .ignored:
                    ignored += 1
                case .unrecognised:
                    unread += 1
            }
        }

        var summary: String {
            var parts = ["Collected \(total): \(recorded) recorded, \(needsReview) need review"]

            if duplicate > 0 {
                parts.append("\(duplicate) already recorded")
            }

            if ignored > 0 {
                parts.append("\(ignored) ignored")
            }

            if unread > 0 {
                parts.append("\(unread) unread")
            }

            return parts.joined(separator: ", ") + "."
        }
    }
}
