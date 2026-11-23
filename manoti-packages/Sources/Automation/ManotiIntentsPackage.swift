//
//  ManotiIntentsPackage.swift
//  Automation
//

import AppIntents

/// Lets Xcode extract the intents declared in this package.
public struct ManotiIntentsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] {
        []
    }
}
