//
//  ICloudStatusServiceTests.swift
//  ManotiTests
//

import CloudKit
import Testing

@testable import AppServices

@MainActor
@Suite("ICloud status")
struct ICloudStatusServiceTests {
    @Test("Every CloudKit account status maps to a case")
    func statusMapping() {
        #expect(ICloudStatusService.map(.available) == .available)
        #expect(ICloudStatusService.map(.noAccount) == .noAccount)
        #expect(ICloudStatusService.map(.restricted) == .restricted)
        #expect(ICloudStatusService.map(.temporarilyUnavailable) == .temporarilyUnavailable)
        #expect(ICloudStatusService.map(.couldNotDetermine) == .couldNotDetermine)
    }

    @Test("Each status has an honest display name")
    func displayNames() {
        #expect(ICloudAccountStatus.unknown.displayName == "Not checked yet")
        #expect(ICloudAccountStatus.available.displayName == "iCloud available")
        #expect(ICloudAccountStatus.noAccount.displayName == "No iCloud account")
        #expect(ICloudAccountStatus.restricted.displayName == "iCloud is restricted")
        #expect(ICloudAccountStatus.temporarilyUnavailable.displayName == "iCloud is temporarily unavailable")
        #expect(ICloudAccountStatus.couldNotDetermine.displayName == "Could not determine iCloud status")
        #expect(ICloudAccountStatus.failed("Offline").displayName == "Could not check iCloud")
        #expect(ICloudAccountStatus.failed("Offline").detail == "Offline")
        #expect(ICloudAccountStatus.available.detail == nil)
    }

    @Test("A new service starts unchecked")
    func startsUnchecked() {
        let service = ICloudStatusService()

        #expect(service.status == .unknown)
        #expect(!service.isChecking)
    }
}
