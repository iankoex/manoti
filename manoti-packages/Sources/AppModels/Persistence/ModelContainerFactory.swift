//
//  ModelContainerFactory.swift
//  AppModels
//

import Foundation
import SwiftData

public enum ModelContainerFactory {
    /// Builds the app's container. Callers may pass no CloudKit identifier for tests or for
    /// the local-only fallback path when iCloud is unavailable.
    public static func make(
        inMemory: Bool = false,
        cloudKitContainerID: String? = nil
    ) throws -> ModelContainer {
        let schema = Schema(ManotiSchema.models)

        let configuration: ModelConfiguration =
            if let cloudKitContainerID {
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    cloudKitDatabase: .private(cloudKitContainerID)
                )
            } else {
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    cloudKitDatabase: .none
                )
            }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
