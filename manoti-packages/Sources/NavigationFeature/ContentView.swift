//
//  ContentView.swift
//  NavigationFeature
//

import AppServices
import InboxFeature
import InsightsFeature
import Modifiers
import PlanFeature
import QuickAddFeature
import ReconcileFeature
import SwiftUI

public enum AppTab: String, CaseIterable, Hashable {
    case home
    case plan
    case add
    case inbox
    case insights
}

public struct ContentView: View {
    /// Written by `OpenInboxIntent`; keep the key in sync with `Sources/Automation/OpenInboxIntent.swift`.
    @AppStorage("manoti.pendingRoute") private var pendingRoute = ""
    @Environment(PrivacyService.self) private var privacyService
    @Environment(NotificationService.self) private var notificationService
    @Environment(WidgetSnapshotService.self) private var widgetSnapshotService
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    @State private var isAdding = false
    @State private var isShowingReconcile = false

    public init() {}

    public var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView(onAdd: presentExpense)
            }

            Tab("Plan", systemImage: "chart.pie", value: AppTab.plan) {
                PlanView()
            }

            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                InboxView()
            }

            Tab("Insights", systemImage: "chart.bar", value: AppTab.insights) {
                InsightsView()
            }

            Tab("Add", systemImage: "plus", value: AppTab.add, role: .prominent) {
                Color.clear
            }
        }
        .minimizeTabBarOnScroll()
        .environment(\.manotiAmountsHidden, privacyService.isAmountsHidden)
        .onChange(of: scenePhase) { _, phase in
            privacyService.scenePhaseChanged(phase.privacyPhase)

            // Permission can be revoked in iOS Settings while the app is suspended.
            if phase == .active {
                refreshNotifications()
            }
        }
        .onAppear(perform: applyPendingRoute)
        .onManotiDataChange {
            refreshNotifications()
            refreshWidgetSnapshot()
        }
        .onChange(of: pendingRoute) { _, _ in
            applyPendingRoute()
        }
        .onChange(of: tab) { previousTab, newTab in
            guard newTab == .add else {
                return
            }

            tab = previousTab == .add ? .home : previousTab
            isAdding = true
        }
        .sheet(isPresented: $isAdding) {
            AddEntryView()
                .environment(\.manotiAmountsHidden, privacyService.isAmountsHidden)
        }
        .sheet(isPresented: $isShowingReconcile) {
            NavigationStack {
                ReconcileView(showsDoneButton: true)
                    .environment(\.manotiAmountsHidden, privacyService.isAmountsHidden)
            }
        }
    }

    private func presentExpense() {
        isAdding = true
    }

    /// The modifier already runs this on appear, so there is no separate `.task`.
    private func refreshNotifications() {
        Task { await notificationService.refresh() }
    }

    private func refreshWidgetSnapshot() {
        widgetSnapshotService.refresh()
    }

    /// A Siri intent cannot drive SwiftUI directly, so it leaves a route behind and this view consumes it.
    private func applyPendingRoute() {
        guard !pendingRoute.isEmpty else {
            return
        }

        if pendingRoute == "inbox" {
            tab = .inbox
        } else if pendingRoute == "reconcile" {
            isShowingReconcile = true
        }

        pendingRoute = ""
    }
}

extension ScenePhase {
    fileprivate var privacyPhase: PrivacyScenePhase {
        switch self {
            case .active: .active
            case .inactive: .inactive
            case .background: .background
            @unknown default: .inactive
        }
    }
}
