//
//  MarkContextIntent.swift
//  Automation
//

import AppIntents
import AppModels
import AppServices
import Foundation
import SwiftData

/// Bound to "When Uber is opened" (or Bolt).
///
/// The next matching payment is suggested as a ride, because iOS does not let an app read another app's
/// notifications.
public struct MarkContextIntent: AppIntent {
    public static let title: LocalizedStringResource = "Mark Ride Context"
    public static let description = IntentDescription(
        "Tells Manoti a ride-hailing app was just opened, so the next matching payment is suggested as a ride."
    )

    @Parameter(title: "Merchant")
    public var merchant: String?

    @Parameter(title: "Minutes")
    public var windowMinutes: Int?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$merchant) for \(\.$windowMinutes) minutes")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = await MainActor.run {
            guard let container = AppStore.container() else {
                return "Manoti could not open its store."
            }

            let name = merchant ?? "Uber"
            let minutes = windowMinutes ?? 60

            do {
                try CategoriserService(context: container.mainContext).openContext(
                    merchant: name,
                    minutes: minutes,
                    sourceApp: name
                )
                return "Manoti will suggest a ride for the next \(minutes) minutes."
            } catch {
                return "Manoti could not set the context: \(error.localizedDescription)"
            }
        }

        // The dialog makes Shortcuts and Siri say the outcome; the value stays for flows that consume it.
        return .result(value: summary, dialog: "\(summary)")
    }
}
