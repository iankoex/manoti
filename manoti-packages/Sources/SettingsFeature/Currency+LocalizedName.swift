//
//  Currency+LocalizedName.swift
//  SettingsFeature
//

import AppModels
import Foundation

extension Currency {
    /// The localized currency name, e.g. "Kenyan Shilling".
    var localizedName: String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
