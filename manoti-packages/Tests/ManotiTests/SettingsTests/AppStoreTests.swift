//
//  AppStoreTests.swift
//  ManotiTests
//

import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("AppStore")
struct AppStoreTests {
    private enum StoreFailure: Error {
        case unavailable
    }

    @Test("Persistent store failures are reported, never replaced with memory")
    func failureIsReported() {
        let resolved = AppStore.resolve(
            cloudKit: { throw StoreFailure.unavailable },
            local: { throw StoreFailure.unavailable }
        )

        #expect(resolved == nil)
    }

    @Test("A local store is used when CloudKit is unavailable")
    func localFallback() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let resolved = AppStore.resolve(
            cloudKit: { throw StoreFailure.unavailable },
            local: { container }
        )

        #expect(resolved === container)
    }
}
