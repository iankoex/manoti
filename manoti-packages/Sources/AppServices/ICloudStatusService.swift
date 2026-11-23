//
//  ICloudStatusService.swift
//  AppServices
//

import CloudKit
import Foundation
import Observation

public enum ICloudAccountStatus: Equatable, Sendable {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case failed(String)

    public var displayName: String {
        switch self {
            case .unknown:
                "Not checked yet"
            case .available:
                "iCloud available"
            case .noAccount:
                "No iCloud account"
            case .restricted:
                "iCloud is restricted"
            case .temporarilyUnavailable:
                "iCloud is temporarily unavailable"
            case .couldNotDetermine:
                "Could not determine iCloud status"
            case .failed:
                "Could not check iCloud"
        }
    }

    /// The underlying error text for a failed check, when there is one.
    public var detail: String? {
        if case .failed(let message) = self {
            return message
        }

        return nil
    }
}

/// Reads the system's iCloud account status.
///
/// This never writes to iCloud and never reports sync progress; those are owned by
/// CloudKit and the system.
@Observable
public final class ICloudStatusService {
    public private(set) var status: ICloudAccountStatus = .unknown
    public private(set) var isChecking = false

    private let containerIdentifier: String

    public init(containerIdentifier: String = AppStore.cloudKitContainerID) {
        self.containerIdentifier = containerIdentifier
    }

    public func refresh() async {
        guard !isChecking else {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let accountStatus = try await CKContainer(identifier: containerIdentifier).accountStatus()
            status = ICloudStatusService.map(accountStatus)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    public static func map(_ accountStatus: CKAccountStatus) -> ICloudAccountStatus {
        switch accountStatus {
            case .available:
                .available
            case .noAccount:
                .noAccount
            case .restricted:
                .restricted
            case .temporarilyUnavailable:
                .temporarilyUnavailable
            case .couldNotDetermine:
                .couldNotDetermine
            @unknown default:
                .unknown
        }
    }
}
