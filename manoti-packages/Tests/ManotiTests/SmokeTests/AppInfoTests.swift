//
//  AppInfoTests.swift
//  ManotiTests
//

import Testing

@testable import AppModels

@Suite("AppInfo")
struct AppInfoTests {
    @Test("App name is Manoti")
    func appName() {
        #expect(AppInfo.name == "Manoti")
    }
}
