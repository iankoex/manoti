//
//  ManotiColor.swift
//  Modifiers
//

import AppPackageExtensions
import SwiftUI

public enum ManotiColor {
    public static let fallback = Color(white: 0.5)

    public static func forHex(_ hex: String) -> Color {
        guard let components = HexColor.rgb(from: hex) else {
            return fallback
        }

        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}
