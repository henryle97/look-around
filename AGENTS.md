# Project: LookAround

A native macOS menu-bar break-reminder app built with SwiftUI, compiled
entirely with the Command Line Tools — no Xcode project, no XCUITest.

- Menu-bar-only app (`LSUIElement`, no Dock icon) via `NSStatusItem` + `NSPopover`.
- `BreakScheduler` is a 1-second timer state machine driving regular/planned
  breaks, snoozing, Smart Pause, and wellness reminders.
- Settings persist as JSON in `UserDefaults` via `SettingsStore`.

## Tech Stack

- Swift 6.1, SwiftUI + AppKit
- macOS 13+, Apple Silicon only (`arm64-apple-macosx13.0`)
- No external package dependencies (single executable target, see `Package.swift`)
- Compiled directly with `swiftc` (not `xcodebuild`) — see `build.sh`

## Quality Gates

After making any code change:

- MUST run `./build.sh` to build (compiles with `swiftc`, bundles the
  `.app`, ad-hoc signs). Fix any build errors and repeat.
- SHOULD run `./scripts/test-unit.sh` if you touched `Models.swift`,
  `SmartPause.swift`, `Helpers.swift`, or `SettingsStore.swift`. Fix any
  failures and repeat.
- SHOULD run the relevant end-to-end test, e.g. `./scripts/test-ui.sh` or
  `./scripts/test-settings.sh`. Fix any failures and repeat.

After making major changes, SHOULD run the full UI test suite:
`for f in scripts/test-*.sh; do $f || break; done`. Fix any failures and repeat.

There is no linter/formatter configured in this repo.

## Commands

- `swift build` — alternate build via SwiftPM, for full-Xcode toolchains
  only (the CLT-only SwiftPM linker is broken here; `build.sh` is the
  supported path in this environment)
- `open LookAround.app` — launch the built app
- `./scripts/package-dmg.sh` — build a release DMG (stamps the version
  into `Info.plist` from a git tag)
- `./scripts/bump-cask.sh`, `./scripts/test-cask.sh` — Homebrew Cask maintenance

## Architecture

- `Sources/LookAround/LookAroundApp.swift` — `@main` App entry, MenuBarExtra/Settings scenes, AppDelegate
- `Sources/LookAround/Models.swift` — break/office-hours/planned/smart-pause/wellness/appearance/automation/stats types
- `Sources/LookAround/SettingsStore.swift` — `ObservableObject` settings + JSON persistence
- `Sources/LookAround/BreakScheduler.swift` — the core timer state machine
- `Sources/LookAround/ActivityProbe.swift`, `SmartPause.swift` — idle/fullscreen detection and pause-rule evaluation (permission-free)
- `Sources/LookAround/WindowManager.swift`, `BreakViews.swift` — break overlay, pre-break and floating-countdown windows/views
- `Sources/LookAround/MenuBarView.swift`, `SettingsView.swift`, `SettingsPages.swift`, `SettingsPages2.swift` — menu-bar dropdown and tabbed settings UI
- `Sources/LookAround/Theme.swift` — AppTheme / Liquid Glass styling
- `tools/axdrive/` — Accessibility-API driver used for UI testing (no Xcode, so no XCUITest)
- `scripts/test-*.sh` — end-to-end UI test suites driven by `axdrive`
- `Tests/LookAroundTests/` — standalone unit-test binary for pure logic (no XCTest — see below)
- `scripts/test-unit.sh` — compiles and runs `Tests/LookAroundTests/`
- `packaging/homebrew/` — Homebrew Cask source; `.github/workflows/release.yml` builds and publishes the DMG on `v*` tags

## Workflows

### Agent-driven UI testing (no Xcode/XCUITest)

Apply whenever you modify UI behavior: how to add accessibility
identifiers, how to launch/write/run the `axdrive`-based test scripts,
and known `axdrive` quirks.
Read `./docs/ui-testing.md`.

### Unit testing pure logic (no XCTest/`swift test`)

Apply whenever you touch scheduling rules, settings persistence, or
pause-reason evaluation: what's in/out of scope for `Tests/LookAroundTests/`,
why `UserDefaults.standard` is safe to use directly there, and how to add a
test or a new source file to the harness.
Read `./docs/unit-testing.md`.

## Development Guidelines

- **Style**: Prefer self-documenting code over comments; comments should explain intent.
- **Git**: Read-only operations allowed. Use `git grep` and `git ls-files` for searching.
- Give every interactive view a stable `.accessibilityIdentifier("…")`
  (convention: `area.control`) — never select by screen coordinates in
  tests. See `docs/ui-testing.md` for the full convention and pitfalls.
- Never leave a stray `LookAround` process running after a test — every
  test script should `axdrive terminate` at both start and end.

### Forbidden Patterns

- Don't put `.accessibilityIdentifier` on a custom View struct's root
  (a page body, an overlay `ZStack`, …) — it shadows all descendants'
  identifiers. Tag leaf controls instead.
- Don't invoke `xcodebuild`/XCUITest — this environment has no Xcode.
