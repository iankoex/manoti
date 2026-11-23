//
//  ReconcileSummaryIntent.swift
//  Automation
//

import AppIntents
import AppModels
import AppServices
import Foundation
import SwiftData

/// Finalises a reconciliation run and returns the counts line.
///
/// Safe to rerun: an already-finalised session returns the same summary instead of failing.
public struct ReconcileSummaryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Finish Reconciliation"
    public static let description = IntentDescription(
        "Matches the collected messages against the ledger and returns the reconciliation summary."
    )

    @Parameter(title: "Session Token")
    public var sessionToken: String?

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Finish reconciliation") {
            \.$sessionToken
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = await MainActor.run { () -> String in
            guard let container = AppStore.container() else {
                return "Manoti could not open its store."
            }

            let service = ReconciliationService(context: container.mainContext)

            do {
                guard let session = try service.session(token: sessionToken) else {
                    return "No reconciliation run yet. Collect messages first."
                }

                return try service.summary(for: session).displayText
            } catch {
                return "Manoti could not finish reconciliation: \(error.localizedDescription)"
            }
        }

        return .result(value: summary, dialog: "\(summary)")
    }
}
