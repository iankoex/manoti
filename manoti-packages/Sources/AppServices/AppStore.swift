//
//  AppStore.swift
//  AppServices
//

import AppModels
import Foundation
import SwiftData

/// One container shared by the app and by App Intents, so a background ingest writes to the
/// same store the UI reads.
@MainActor
public enum AppStore {
    public static let cloudKitContainerID = "iCloud.com.iankoex.manoti"

    private static var cached: ModelContainer?

    public static func container() -> ModelContainer? {
        if let cached {
            return cached
        }

        let container = resolve(
            cloudKit: { try ModelContainerFactory.make(cloudKitContainerID: cloudKitContainerID) },
            local: { try ModelContainerFactory.make() }
        )

        cached = container
        return container
    }

    /// Resolves the persistent store. There is deliberately no in-memory fallback: a store
    /// that cannot be opened must surface as a failure, not silently accept writes that
    /// disappear when the process exits.
    static func resolve(
        cloudKit: () throws -> ModelContainer,
        local: () throws -> ModelContainer
    ) -> ModelContainer? {
        if let container = try? cloudKit() {
            return container
        }

        return try? local()
    }
}
