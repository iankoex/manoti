//
//  KeyboardModifiers.swift
//  Modifiers
//

import SwiftUI

extension View {
    /// Decimal keypad on iOS; a no-op elsewhere so package code stays cross-platform.
    @ViewBuilder
    public func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Disables smart text helpers where the platform supports them.
    @ViewBuilder
    public func plainTextInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
}
