# Manoti

A private expense and budget tracker for iPhone. Everything stays on the device and in the
user's own CloudKit private database — no server, no account, no analytics.

## Layout

```
Manoti/                     app target (entry point, assets, entitlements)
manoti-packages/            all Swift source, as a local Swift package
  Sources/AppModels/        SwiftData models, money, seed taxonomy
  Sources/AppServices/      @Observable services over the ModelContext
  Sources/AppPackageExtensions/  small shared helpers (hex colours, logging, notifications)
  Sources/Modifiers/        design tokens and reusable views
  Sources/NavigationFeature/     app shell, Home, tab routing
  Sources/AccountsFeature/       account list, editor, detail
  Sources/QuickAddFeature/       keypad-first expense entry
  Sources/LedgerFeature/         ledger row presentation
  Sources/TransfersFeature/      transfer form
  Tests/ManotiTests/        Swift Testing suites
```

The app target is a *folder reference*; everything inside is compiled by the app. Keep
source in the package, not in `Manoti/`.

## Build and test

```bash
swift test --package-path manoti-packages     # fast domain-layer tests (macOS)
open Manoti.xcodeproj                         # run the app in a simulator
```

The package builds in Swift 6 language mode with `MainActor` default isolation. Pure value
types (`Money`, `Currency`, `FXRate`, `ExchangeRateBook`, enums, seeds) are explicitly
`nonisolated`; services and views are main-actor by default.

## Conventions

- One type per file, named after the type. Extensions as `Type+Purpose.swift`.
- Views end in `View`, cells in `Cell`; services are `@Observable final class XService`
  injected with `.environment(...)`.
- `.swift-format` at the repo root; run
  `swift format --configuration .swift-format --in-place --recursive manoti-packages/Sources manoti-packages/Tests Manoti`.
- Money is `Int64` minor units plus an ISO currency code. Never `Double`.
- No third-party dependencies.

## Identity

- Bundle id: `com.iankoex.manoti`
- iCloud container: `iCloud.com.iankoex.manoti`
- App group: `group.com.iankoex.manoti`

## Status

Milestone 1 (foundation) and the core of Milestone 2 (ingestion) are implemented.

- Accounts with opening balances, colours, icons, currencies and archived state.
- Expenses, income and adjustments with fees; balances derived from the ledger only.
- One Add sheet with Expense / Income / Transfer modes.
- Transfers between accounts, same-currency and cross-currency, fee on the out leg.
- Exchange rates with a latest-per-pair book; net worth converts to the display currency.
- Keypad-first entry, account detail ledger, 7-day spend chart (Swift Charts).
- Bank/M-Pesa parser with editable rule sets, seeded for M-Pesa and I&M Bank, verified
  against seven real messages.
- Inbox for messages that need an account or category, with merchant memory, amount/time
  smart rules, and an in-app rules playground.
- App Intents: Collect Payment Message, Collect Payment Messages, Log Payment, Mark Ride
  Context; plus a Shortcuts setup guide.
- CloudKit private database with a local-only fallback if sync is unavailable.

Not yet built: the reconcile shortcut (Milestone 3), full insights (Milestone 4),
notifications/lock/widgets/export (Milestone 5), budget (Milestone 6).
