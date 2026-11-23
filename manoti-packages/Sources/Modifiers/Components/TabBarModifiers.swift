//
//  TabBarModifiers.swift
//  Modifiers
//

import SwiftUI

extension View {
    /// iOS 26+ Liquid Glass tab bar that recedes while scrolling. No-op on macOS.
    @ViewBuilder
    public func minimizeTabBarOnScroll() -> some View {
        #if os(iOS)
        tabBarMinimizeBehavior(.onScrollDown)
        #else
        self
        #endif
    }
}
