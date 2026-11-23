//
//  SettingsToolbarItem.swift
//  SettingsFeature
//

import SwiftUI

/// The gear shown on every main tab. It owns its own Settings sheet, so screens only add
/// the toolbar item rather than repeating presentation state.
public struct SettingsToolbarItem: ToolbarContent {
    public init() {}

    public var body: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            SettingsToolbarButton()
        }
        #else
        ToolbarItem(placement: .navigation) {
            SettingsToolbarButton()
        }
        #endif
    }
}

public struct SettingsToolbarButton: View {
    @State private var isShowingSettings = false

    public init() {}

    public var body: some View {
        Button("Settings", systemImage: "gearshape") {
            isShowingSettings = true
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }
}
