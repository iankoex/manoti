// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "manoti-packages",
    defaultLocalization: "en",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "AppModels", targets: ["AppModels"]),
        .library(name: "AppPackageExtensions", targets: ["AppPackageExtensions"]),
        .library(name: "AppServices", targets: ["AppServices"]),
        .library(name: "Modifiers", targets: ["Modifiers"]),
        .library(name: "NavigationFeature", targets: ["NavigationFeature"]),
        .library(name: "AccountsFeature", targets: ["AccountsFeature"]),
        .library(name: "PlanFeature", targets: ["PlanFeature"]),
        .library(name: "BudgetFeature", targets: ["BudgetFeature"]),
        .library(name: "QuickAddFeature", targets: ["QuickAddFeature"]),
        .library(name: "LedgerFeature", targets: ["LedgerFeature"]),
        .library(name: "TransfersFeature", targets: ["TransfersFeature"]),
        .library(name: "InboxFeature", targets: ["InboxFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "Automation", targets: ["Automation"]),
        .library(name: "RulesFeature", targets: ["RulesFeature"]),
        .library(name: "ReconcileFeature", targets: ["ReconcileFeature"]),
        .library(name: "LoansFeature", targets: ["LoansFeature"]),
        .library(name: "InvestmentsFeature", targets: ["InvestmentsFeature"]),
        .library(name: "InsightsFeature", targets: ["InsightsFeature"]),
    ],
    targets: [
        .target(
            name: "AppModels",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AppPackageExtensions",
            dependencies: ["AppModels"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AppServices",
            dependencies: ["AppModels", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Modifiers",
            dependencies: ["AppModels", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "NavigationFeature",
            dependencies: [
                "AppModels",
                "AppServices",
                "Modifiers",
                "AccountsFeature",
                "PlanFeature",
                "QuickAddFeature",
                "LedgerFeature",
                "TransfersFeature",
                "ReconcileFeature",
                "InboxFeature",
                "SettingsFeature",
                "LoansFeature",
                "InsightsFeature",
                "AppPackageExtensions",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "InsightsFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions", "SettingsFeature"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AccountsFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "LedgerFeature", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PlanFeature",
            dependencies: [
                "AppModels", "AppServices", "Modifiers", "InvestmentsFeature", "BudgetFeature", "TransfersFeature",
                "SettingsFeature",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "BudgetFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "QuickAddFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions", "TransfersFeature"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "LedgerFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RulesFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions", "Automation"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "ReconcileFeature",
            dependencies: [
                "AppModels", "AppServices", "Modifiers", "AppPackageExtensions", "LedgerFeature",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Automation",
            dependencies: ["AppModels", "AppServices", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "InboxFeature",
            dependencies: [
                "AppModels", "AppServices", "Modifiers", "AppPackageExtensions", "RulesFeature", "SettingsFeature",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SettingsFeature",
            dependencies: [
                "AppModels", "AppServices", "Modifiers", "AppPackageExtensions", "RulesFeature",
                "ReconcileFeature",
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TransfersFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "LoansFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "InvestmentsFeature",
            dependencies: ["AppModels", "AppServices", "Modifiers", "AppPackageExtensions"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ManotiTests",
            dependencies: [
                "AppModels", "AppPackageExtensions", "AppServices", "Automation", "LoansFeature", "InvestmentsFeature",
                "BudgetFeature", "LedgerFeature", "SettingsFeature", "ReconcileFeature", "InsightsFeature",
                "QuickAddFeature", "TransfersFeature",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
