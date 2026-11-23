//
//  ManotiDataChangeModifier.swift
//  Modifiers
//

import AppPackageExtensions
import Foundation
import SwiftUI

extension View {
    /// Runs `action` on appear and whenever a Manoti service persists a change.
    ///
    /// Uses Swift's async sequence support instead of Combine, so the refresh task is tied
    /// to the view's lifetime and cancelled automatically when it disappears.
    public func onManotiDataChange(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(ManotiDataChangeModifier(action: action))
    }
}

private struct ManotiDataChangeModifier: ViewModifier {
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.task {
            action()

            for await _ in NotificationCenter.default.notifications(named: .manotiDataChanged) {
                action()
            }
        }
    }
}
