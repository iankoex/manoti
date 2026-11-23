//
//  AppServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("AppService settings")
struct AppServiceTests {
    private func makeService() throws -> (AppService, ModelContext) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        return (AppService(context: context), context)
    }

    @Test("Changing the display currency persists")
    func displayCurrency() throws {
        let (service, context) = try makeService()

        try service.setDisplayCurrency("USD")

        #expect(service.displayCurrency.code == "USD")
        #expect(AppService(context: context).displayCurrency.code == "USD")
    }

    @Test("An unsupported display currency is rejected")
    func unsupportedCurrency() throws {
        let (service, _) = try makeService()

        #expect(throws: SettingsError.unsupportedCurrency) {
            try service.setDisplayCurrency("XYZ")
        }
        #expect(service.displayCurrency.code == "KES")
    }

    @Test("Notifications are opt-in and persist")
    func notificationsOptIn() throws {
        let (service, context) = try makeService()

        #expect(!service.notificationsEnabled)

        try service.setNotificationsEnabled(true)
        #expect(service.notificationsEnabled)
        #expect(AppService(context: context).notificationsEnabled)

        try service.setNotificationsEnabled(false)
        #expect(!AppService(context: context).notificationsEnabled)
    }

    @Test("The week start is persisted and validated")
    func weekStartsOn() throws {
        let (service, context) = try makeService()

        try service.setWeekStartsOn(1)

        #expect(service.weekStartsOn == 1)
        #expect(AppService(context: context).weekStartsOn == 1)
        #expect(throws: SettingsError.invalidWeekStart) {
            try service.setWeekStartsOn(9)
        }
    }

    @Test("The default reinvestment rate is editable and persisted")
    func reinvestmentRate() throws {
        let (service, context) = try makeService()

        #expect(service.reinvestmentRateBasisPoints == AppSettings.defaultReinvestmentRateBasisPoints)

        try service.setReinvestmentRateBasisPoints(1050)

        #expect(service.reinvestmentRateBasisPoints == 1050)
        #expect(AppService(context: context).reinvestmentRateBasisPoints == 1050)
        #expect(throws: SettingsError.invalidRate) {
            try service.setReinvestmentRateBasisPoints(6000)
        }
    }

    @Test("The default withholding tax is editable and persisted")
    func withholdingTax() throws {
        let (service, context) = try makeService()

        #expect(service.withholdingTaxBasisPoints == AppSettings.defaultWithholdingTaxBasisPoints)

        try service.setWithholdingTaxBasisPoints(1250)

        #expect(service.withholdingTaxBasisPoints == 1250)
        #expect(AppService(context: context).withholdingTaxBasisPoints == 1250)
        #expect(throws: SettingsError.invalidRate) {
            try service.setWithholdingTaxBasisPoints(10_001)
        }
    }

    @Test("Privacy mode is off by default and persists")
    func privacyMode() throws {
        let (service, context) = try makeService()

        #expect(!service.privacyModeEnabled)

        try service.setPrivacyModeEnabled(true)

        #expect(service.privacyModeEnabled)
        #expect(AppService(context: context).privacyModeEnabled)

        try service.setPrivacyModeEnabled(false)

        #expect(!service.privacyModeEnabled)
    }

    @Test("Raw message retention is on by default and persists")
    func keepRawMessages() throws {
        let (service, context) = try makeService()

        #expect(service.keepRawMessages)

        try service.setKeepRawMessages(false)

        #expect(!service.keepRawMessages)
        #expect(!AppService(context: context).keepRawMessages)

        try service.setKeepRawMessages(true)

        #expect(service.keepRawMessages)
        #expect(AppService(context: context).keepRawMessages)
    }
}
