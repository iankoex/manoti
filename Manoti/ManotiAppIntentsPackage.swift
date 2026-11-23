//
//  ManotiAppIntentsPackage.swift
//  Manoti
//

import AppIntents
import Automation

/// Bridges the intents declared in the `manoti-packages` Swift package into the app target.
///
/// Xcode's App Intents metadata processor only extracts intents from package targets when the app target
/// declares an `AppIntentsPackage` that includes them, which is what makes Siri, Spotlight and the
/// Shortcuts app discover Manoti's actions.
struct ManotiAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [ManotiIntentsPackage.self]
    }
}
