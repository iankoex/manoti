//
//  ScheduleMismatch.swift
//  AppServices
//

import Foundation

/// A difference between an expected coupon and what was actually recorded.
public struct ScheduleMismatch: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case missing
        case amountMismatch
        case unexpected
    }

    public let id: UUID
    public let kind: Kind
    public let expectedDate: Date?
    public let actualDate: Date?
    public let expectedNetMinor: Int64?
    public let actualNetMinor: Int64?

    public init(
        kind: Kind,
        expectedDate: Date? = nil,
        actualDate: Date? = nil,
        expectedNetMinor: Int64? = nil,
        actualNetMinor: Int64? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.expectedDate = expectedDate
        self.actualDate = actualDate
        self.expectedNetMinor = expectedNetMinor
        self.actualNetMinor = actualNetMinor
    }

    public var message: String {
        switch kind {
            case .missing:
                "No payment recorded for the expected coupon."
            case .amountMismatch:
                "The recorded net coupon differs from the schedule."
            case .unexpected:
                "A coupon was recorded outside the expected schedule."
        }
    }
}
