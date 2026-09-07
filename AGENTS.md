# Agent-driven UI testing for LookAround

This repo is intentionally Xcode-free (`build.sh` compiles with `swiftc`
alone — see README.md). Only the Command Line Tools are installed here,
so **XCUITest is not available** (`xcodebuild` errors with "requires
Xcode"). End-to-end UI testing instead drives the real, running app
through the macOS Accessibility (AX) API, via the small `axdrive` tool in
`tools/axdrive/`. Same idea as XCUITest — find elements by a stable
identifier, act on them, assert on the result — different mechanism.

## After modifying UI behavior

1. Build: `./build.sh`.
2. Give every interactive view a stable `.accessibilityIdentifier("…")`
   (convention: `area.control`, e.g. `settings.screenBreaks.breakDuration`,
   `menubar.settingsButton`). Never select by screen coordinates.
   - A `ChipStepper` (see `SettingsView.swift`) takes an `id:` and exposes
     both the stepper (`id`, drivable via increment/decrement) and its
     formatted label (`"\(id).value"`, readable).
   - `SettingsView.sideRow` derives its identifier from `SettingsRoute`
     automatically (`settings.nav.<route.navSlug>`) — add new routes to
     `navSlug` when you add a route.
3. Launch deterministically: `--ui-testing --reset-state` (see
   `UITesting` in `LookAroundApp.swift`). `--reset-state` wipes
   `SettingsStore.persistenceKey` before the store loads; `--ui-testing`
   is available for tests to check/branch on later.
4. If there's no existing test for the changed behavior, add one to
   `scripts/test-ui.sh` (or a new `scripts/test-*.sh`), following the
   existing "break duration persists" scenario as a template.
5. Run `./scripts/test-ui.sh`. On failure: inspect the assertion output,
   fix the root cause, rerun the failing script, then rerun the full
   suite (`for f in scripts/test-*.sh; do $f || break; done`).
6. Never leave a stray `LookAround` process running — every script should
   `axdrive terminate` at the end (and at the start, before it launches).

## `axdrive` cheat sheet

```
axdrive launch <path-to-.app> [--arg X] [--env K=V]   # NSWorkspace launch
axdrive terminate <bundle-id>
axdrive menu-click <bundle-id>                        # click the status-bar icon
axdrive find <bundle-id> <identifier>                 # role/enabled/value
axdrive click <bundle-id> <identifier>                # AXPress
axdrive increment/decrement <bundle-id> <id> [count]  # for ChipStepper
axdrive read <bundle-id> <identifier>                 # AXValue as string
axdrive tree <bundle-id>                               # dump the AX tree (debugging)
```

Bundle ID: `com.lookaround.app`. Requires Accessibility permission for
whatever process runs `axdrive` (grant once under System Settings →
Privacy & Security → Accessibility).

Known quirks:
- The `MenuBarExtra` popover is **not** part of `kAXWindows` — it lives
  under the app's own `AXExtrasMenuBar` attribute, which is why
  `menu-click` is a separate command from `click`.
- The very first `menu-click` right after a fresh launch can be a no-op
  (timing race with app startup) — poll for the expected identifier and
  retry rather than assuming one click is enough (see `open_popover` in
  `scripts/test-ui.sh`).
- Any UI change lands after SettingsStore's 400ms debounced autosave —
  sleep past that before killing the app in a persistence test.

## If you outgrow this

If Xcode ever gets installed here, XCUITest remains the better long-term
choice (native assertions, `.xcresult` reports, CI integration, code
coverage) — see the "Full XCUITest" option considered and rejected for
this environment. It would slot in alongside `axdrive`, not replace the
`accessibilityIdentifier` work above, which both approaches share.
