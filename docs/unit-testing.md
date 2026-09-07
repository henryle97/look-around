# Unit testing LookAround's pure logic

This repo is intentionally Xcode-free (`build.sh` compiles with `swiftc`
alone — see README.md). That rules out **both** of the usual Swift unit-test
paths, not just XCUITest:

- `swift test` / `swift build` fail before compiling a single test — the
  CLT-only SwiftPM linker can't even resolve `Package.swift`'s own
  `PackageDescription` symbols (`Undefined symbols for architecture arm64:
  ...PackageDescription.Package...`).
- XCTest needs Xcode's `xctest` utility (`xcrun: error: unable to find
  utility "xctest"`), which the Command Line Tools don't ship.

So `Tests/LookAroundTests/` is a small dependency-free test harness
(`TestKit.swift`) compiled directly with `swiftc` into a standalone binary —
same idea as `tools/axdrive` for UI testing, different problem. `expectTrue`,
`expectFalse`, `expectEqual`, `expectNil`, `expectNotNil` throw
`ExpectationFailure` on mismatch; `TestRunner.run(name:)` catches it (or any
other thrown error) per-test, so one failure doesn't abort the suite.

Run: `./scripts/test-unit.sh`.

## What's in scope here

This harness is for **pure logic that doesn't need a running app** —
scheduling rules, decode/persistence, pause-reason evaluation. It's the
counterpart to `docs/ui-testing.md`, not a replacement: anything that needs
the real menu-bar UI, window lifecycle, or Accessibility tree still belongs
in `scripts/test-*.sh` via `axdrive`.

Currently covered:
- `Models.swift` — `OfficeHours.isActive` (day/time window, including the
  overnight-wrap case), `AppearanceSettings`' custom `Codable` (old
  snapshots missing newer keys must still decode).
- `SmartPause.swift` — `SmartPauseEvaluator.pauseReason`, including the
  check-priority order between meetings/screen-sharing/video/deep-focus/
  gaming/focus-mode.
- `Helpers.swift` — `TimeFmt`'s formatting edge cases (zero, negative,
  hour rollover).
- `SettingsStore.swift` — save/load round-trip and `resetAll()`, against
  the real `UserDefaults.standard` API (see below for why that's fine here).

**Not covered yet:** `BreakScheduler`'s state machine (`tick()` and most of
its supporting logic — snooze accounting, planned-break due-window,
next-break-kind rotation) is `private` and entangled with `ActivityProbe`/
`CalendarMonitor`/`UserNotifications` calls, so it can't be driven directly
today. If you need to unit-test a piece of it, extract that piece into a
`static`/pure function or a separate type first (the way `SmartPauseEvaluator`
already is), add it to `SOURCES` in `scripts/test-unit.sh`, then test the
extracted piece — don't try to instantiate `BreakScheduler` itself in this
harness.

## Adding a test

1. Pick (or add) a file in `Tests/LookAroundTests/` and a
   `func register<Area>Tests(_ r: TestRunner)` function, following
   `OfficeHoursTests.swift` as a template.
2. Register it from `Tests/LookAroundTests/main.swift`.
3. If the test needs a new `Sources/LookAround/*.swift` file, add it to the
   `SOURCES` array in `scripts/test-unit.sh` — but first check it has **no
   import of AppKit-heavy UI code and no `@main`**: everything currently
   listed there (`Models.swift`, `SmartPause.swift`, `ActivityProbe.swift`,
   `Helpers.swift`, `SettingsStore.swift`) only imports `Foundation`/
   `Combine`/`AppKit`-for-static-data, with no code that actually talks to
   `NSWorkspace`/`UserNotifications`/etc. at file-scope. Pulling in
   `BreakScheduler.swift`, any view file, or `LookAroundApp.swift` (has
   `@main`, would collide with `Tests/LookAroundTests/main.swift`'s own
   entry point) will not compile cleanly into this binary as-is.
4. Run `./scripts/test-unit.sh`. On failure, the output line has a
   `file:line` (e.g. `TimeFmtTests.swift:5`) pointing at the failing
   `expect*` call.

### Why it's safe to touch `UserDefaults.standard` directly

`SettingsStore` hardcodes `UserDefaults.standard` (it's not injectable), so
`SettingsStoreTests.swift` exercises the real API rather than a fake. A bare
CLT binary like this test runner gets its own defaults domain — distinct
from the built `.app`'s (keyed by bundle id `com.lookaround.app`) — so it
can't clobber real app settings on the machine running it. Every test still
wipes `SettingsStore.persistenceKey` before and after, the same precaution
`LookAroundApp.swift`'s `--reset-state` takes.

### `SettingsStore`'s debounced autosave doesn't fire here

`SettingsStore.init()` schedules its autosave on a 400ms `.debounce(...,
scheduler: RunLoop.main)` — which never runs because this test binary has no
spinning `RunLoop.main` (it just runs test bodies synchronously and exits).
That's fine: call `store.save()` explicitly instead of waiting on it, the
same way `SettingsStoreTests.swift` does.

## If you outgrow this

If Xcode ever gets installed here, XCTest (via `swift test` or
`xcodebuild test`) is the better long-term choice — richer assertions,
`.xcresult` reports, CI integration, code coverage, async test support. It
would slot in alongside this harness during a migration, not require
rewriting `BreakScheduler` first.
