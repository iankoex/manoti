//
//  PrivacyToolbarButton.swift
//  Modifiers
//

import SwiftUI

/// The shared eye control shown on the main tabs.
///
/// Screens pass the current masking state and the reveal/hide action; `AppServices` stays
/// out of this module.
public struct PrivacyToolbarButton: View {
    private let isHidden: Bool
    private let action: () -> Void

    public init(isHidden: Bool, action: @escaping () -> Void) {
        self.isHidden = isHidden
        self.action = action
    }

    public var body: some View {
        Button(
            isHidden ? "Show amounts" : "Hide amounts",
            systemImage: isHidden ? "eye.slash" : "eye",
            action: action
        )
    }
}
