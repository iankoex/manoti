//
//  HexColor.swift
//  AppPackageExtensions
//

import Foundation

/// Minimal hex parsing shared by design tokens and model colours.
nonisolated public enum HexColor {
    /// Parses `#RRGGBB` or `RRGGBB` into normalised components, or `nil` when malformed.
    public static func rgb(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let raw = UInt32(value, radix: 16) else {
            return nil
        }

        return (
            red: Double((raw >> 16) & 0xFF) / 255,
            green: Double((raw >> 8) & 0xFF) / 255,
            blue: Double(raw & 0xFF) / 255
        )
    }

    /// Returns a normalised `RRGGBB` string, or `nil` when malformed.
    public static func normalised(_ hex: String) -> String? {
        guard rgb(from: hex) != nil else {
            return nil
        }

        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        return value.uppercased()
    }
}
