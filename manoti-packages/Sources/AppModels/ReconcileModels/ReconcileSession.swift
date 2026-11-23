//
//  ReconcileSession.swift
//  AppModels
//

import Foundation
import SwiftData

/// One reconciliation run over a period, holding the messages a Shortcut collected.
///
/// Counts are stored so a summary can be shown without recomputing, and the ignore list is
/// kept on the session so an explicitly dismissed app row does not reappear in later reads.
@Model
public final class ReconcileSession {
    public var id: UUID = UUID()
    /// Shortcut-supplied identity. Not constrained: a new session may reuse an old token.
    public var token: String = ""
    public var startedAt: Date = Date()
    public var periodStart: Date = Date()
    public var periodEnd: Date = Date()
    public var messageCount: Int = 0
    public var matchedCount: Int = 0
    public var messageOnlyCount: Int = 0
    public var appOnlyCount: Int = 0
    public var ignoredEntryIDsJSON: String = "[]"
    public var isFinalised: Bool = false
    public var completedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ReconcileMessage.session)
    public var messages: [ReconcileMessage]?

    public init(token: String, periodStart: Date, periodEnd: Date, startedAt: Date = Date()) {
        self.id = UUID()
        self.token = token
        self.startedAt = startedAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.completedAt = nil
    }

    /// Ledger rows the user has explicitly dismissed for this session.
    public var ignoredEntryIDs: Set<UUID> {
        guard let data = ignoredEntryIDsJSON.data(using: .utf8),
            let strings = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    public func storeIgnoredEntryIDs(_ ids: Set<UUID>) {
        let strings = ids.map(\.uuidString).sorted()
        guard let data = try? JSONEncoder().encode(strings),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        ignoredEntryIDsJSON = json
    }
}
