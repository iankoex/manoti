//
//  PrivacyServiceTests.swift
//  ManotiTests
//

import Foundation
import SwiftData
import Testing

@testable import AppModels
@testable import AppServices

@MainActor
@Suite("PrivacyService")
struct PrivacyServiceTests {
    private func makeService(privacyModeEnabled: Bool = false) throws -> (PrivacyService, AppService) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()

        let appService = AppService(context: context)

        if privacyModeEnabled {
            try appService.setPrivacyModeEnabled(true)
        }

        return (PrivacyService(appService: appService), appService)
    }

    @Test("A launch with the setting on starts hidden")
    func startsHidden() throws {
        let (privacy, _) = try makeService(privacyModeEnabled: true)

        #expect(privacy.isAmountsHidden)
    }

    @Test("A launch with the setting off starts shown")
    func startsShown() throws {
        let (privacy, _) = try makeService()

        #expect(!privacy.isAmountsHidden)
    }

    @Test("Reveal and hide are explicit")
    func revealAndHide() throws {
        let (privacy, _) = try makeService(privacyModeEnabled: true)

        privacy.reveal()
        #expect(!privacy.isAmountsHidden)

        privacy.hide()
        #expect(privacy.isAmountsHidden)
    }

    @Test("Hiding asks the notification layer to clear")
    func hideClearsNotifications() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        try SeedService(context: context).seedIfNeeded()
        let appService = AppService(context: context)

        var cleared = 0
        let privacy = PrivacyService(appService: appService) {
            cleared += 1
        }

        privacy.hide()
        #expect(cleared == 1)
    }

    @Test("Backgrounding re-hides after a reveal")
    func backgroundRehides() throws {
        let (privacy, _) = try makeService(privacyModeEnabled: true)

        privacy.reveal()
        privacy.scenePhaseChanged(.background)

        #expect(privacy.isAmountsHidden)
    }

    @Test("Becoming inactive also re-hides")
    func inactiveRehides() throws {
        let (privacy, _) = try makeService(privacyModeEnabled: true)

        privacy.reveal()
        privacy.scenePhaseChanged(.inactive)

        #expect(privacy.isAmountsHidden)
    }

    @Test("Becoming active never reveals on its own")
    func activeDoesNotReveal() throws {
        let (privacy, _) = try makeService(privacyModeEnabled: true)

        privacy.scenePhaseChanged(.active)

        #expect(privacy.isAmountsHidden)
    }

    @Test("Backgrounding leaves amounts alone when the setting is off")
    func backgroundDoesNotHideWhenOff() throws {
        let (privacy, _) = try makeService()

        privacy.scenePhaseChanged(.background)

        #expect(!privacy.isAmountsHidden)
    }

    @Test("Applying launch state follows the current setting")
    func applyLaunchState() throws {
        let (privacy, appService) = try makeService()

        try appService.setPrivacyModeEnabled(true)
        privacy.applyLaunchState()
        #expect(privacy.isAmountsHidden)

        try appService.setPrivacyModeEnabled(false)
        privacy.applyLaunchState()
        #expect(!privacy.isAmountsHidden)
    }
}
