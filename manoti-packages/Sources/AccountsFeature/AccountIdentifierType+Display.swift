//
//  AccountIdentifierType+Display.swift
//  AccountsFeature
//

import AppModels

extension AccountIdentifierType {
    var displayName: String {
        switch self {
            case .cardLast4: "Card last 4"
            case .accountNumber: "Account number"
            case .phone: "Phone number"
            case .sender: "Sender name"
        }
    }

    var symbolName: String {
        switch self {
            case .cardLast4: "creditcard"
            case .accountNumber: "number"
            case .phone: "phone"
            case .sender: "text.bubble"
        }
    }

    var valuePlaceholder: String {
        switch self {
            case .cardLast4: "5477"
            case .accountNumber: "01234567890123"
            case .phone: "254700000000"
            case .sender: "Sender ID"
        }
    }

    var validationHint: String {
        switch self {
            case .cardLast4: "Exactly the last four digits on the card."
            case .accountNumber: "Digits only, at least four."
            case .phone: "Any common format, e.g. 254700000000, +254 700 000 000 or 0700 000 000."
            case .sender: "The sender name or shortcode shown by Messages."
        }
    }

    var usesNumericKeyboard: Bool {
        self != .sender
    }
}
