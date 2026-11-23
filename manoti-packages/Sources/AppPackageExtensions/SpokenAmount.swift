//
//  SpokenAmount.swift
//  AppPackageExtensions
//

import AppModels
import Foundation

/// Amount text for Siri and Shortcuts, which cannot use the view-level privacy mask.
public enum SpokenAmount {
    public static func describe(_ money: Money, hidden: Bool) -> String {
        hidden ? "an amount" : money.formatted()
    }
}
