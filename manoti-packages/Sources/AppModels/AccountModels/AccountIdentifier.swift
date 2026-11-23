//
//  AccountIdentifier.swift
//  AppModels
//

import Foundation
import SwiftData

nonisolated public enum AccountIdentifierType: String, CaseIterable, Codable, Sendable, Identifiable {
    case cardLast4
    case accountNumber
    case phone
    case sender

    public var id: String { rawValue }

    /// Display ordering. Routing collapses account numbers and phones into one level.
    public var specificity: Int {
        switch self {
            case .cardLast4: 0
            case .accountNumber: 1
            case .phone: 2
            case .sender: 3
        }
    }
}

@Model
public final class AccountIdentifier {
    public var id: UUID = UUID()
    public var value: String = ""
    public var typeRaw: String = AccountIdentifierType.accountNumber.rawValue
    public var account: Account?

    public init(value: String, type: AccountIdentifierType) {
        self.id = UUID()
        self.value = value
        self.typeRaw = type.rawValue
    }

    public var type: AccountIdentifierType {
        get { AccountIdentifierType(rawValue: typeRaw) ?? .accountNumber }
        set { typeRaw = newValue.rawValue }
    }

    public var normalisedValue: String {
        value.filter(\.isNumber)
    }
}
