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
   - A `ChipStepper`/`EditableHMBox` (see `SettingsView.swift`) takes an
     `id:` and exposes both the stepper (`id`, drivable via
     increment/decrement) and its number (`"\(id).value"`, readable *and*
     click-to-edit — click it, then use `axdrive type` to type a value).
     Never apply `.accessibilityIdentifier` to a container that also holds
     another visible leaf (e.g. a unit suffix like "min"/"sec" next to the
     value) — see the AXAttributedDescription quirk below for why that
     silently makes lookups ambiguous instead of erroring.
   - `SettingsView.sideRow` derives its identifier from `SettingsRoute`
     automatically (`settings.nav.<route.navSlug>`) — add new routes to
     `navSlug` when you add a route.
   - ⚠️ NEVER put `.accessibilityIdentifier` on a custom View struct root
     (a page body, the overlay ZStack, …): SwiftUI stamps it over the whole
     subtree and the descendants' own identifiers stop resolving. Tag the
     leaf controls instead (buttons, steppers, toggles, texts). Stamping a
     primitive container (`HStack`/`VStack`) is safe — children keep theirs.
   - To assert "page X rendered", don't use a page-root marker (see above);
     assert on one always-present control id per page instead — see
     `sentinel_for` in `scripts/test-settings.sh`.
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
axdrive attrs <bundle-id> <identifier>                 # dump every AX attribute (debugging)
axdrive click <bundle-id> <identifier>                # AXPress
axdrive increment/decrement <bundle-id> <id> [count]  # for ChipStepper
axdrive type <bundle-id> <digits> [--enter] [--escape] [--clear=N]
                                                        # synthetic keystrokes into whatever's
                                                        # focused — click the field first
axdrive read <bundle-id> <identifier>                 # AXValue as string
axdrive tree <bundle-id>                               # dump the AX tree (debugging)
axdrive shot-window <bundle-id> <title-sub> <out.png>  # capture one window by title
axdrive shot-display <1|2> <out.png>                   # capture a whole display
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
- The popover auto-dismisses when the app deactivates (e.g. a system
  notification banner appears) — re-assert it is open before capturing or
  clicking inside it (see `shot_popup` in `scripts/test-settings.sh`).
- `click` retries its lookup for ~2s because the tree can be mid-mutation
  (a timer-driven window opening/closing) at the moment of one lookup.
- Pressing Quit (or anything that kills the app) usually reports
  `press failed: -25204` — the AX reply round-trip dies with the app even
  though the action lands. Assert on the process being gone instead.
- Off-screen elements in a `ScrollView` ARE exposed (no scrolling needed
  to `find` them) — verified, don't add scroll machinery.
- `screencapture -m` only captures the main display on multi-monitor
  setups; the Settings window may open on another display. Capture windows
  by title (`shot-window`) for review screenshots, both displays
  (`shot-display 1/2`) for popovers/overlays. Review captures land in
  `/tmp/lookaround-screens/` (not committed).
- Any UI change lands after SettingsStore's 400ms debounced autosave —
  sleep past that before killing the app in a persistence test.
- A `Text` that carries a `.accessibilityAction` (used for click-to-edit
  chips — see `ChipStepper`/`EditableHMBox`) gets promoted from
  `AXStaticText` to `AXButton` by the AX bridge, and its label moves out of
  `AXValue`/`AXTitle` into an `AXAttributedDescription` (an
  `NSAttributedString`, not even plain `AXDescription`) — `read`/`find`
  already fall back to it via `axValueDescription`, but `attrs` is the tool
  to reach for if a similarly-promoted element ever reads as empty again.
- `type` sends real HID keyboard events, unlike every other command (which
  act on the AX element directly) — the target app must actually be
  frontmost, so `type` calls `NSRunningApplication.activate()` first. It
  still occasionally drops a keystroke or two (a focus/timing race, not a
  product bug) — retry the whole click → type → read round trip rather
  than assuming one attempt lands (see `type_and_verify` in
  `scripts/test-numeric-entry.sh`). Also note a `TextField` auto-selects
  its full contents on focus, so `--clear=N` should over-clear a bit
  (extra backspaces on an empty field are harmless no-ops) rather than
  count exactly N existing characters.
- **Poll for the value you expect; never sleep a fixed amount and read.**
  SwiftUI regenerates the AX tree when it re-renders, and it only re-renders
  when something actually changes — so there is no fixed delay that is both
  quick and safe. This bit once for real: `test-numeric-entry.sh` passed on a
  flat `sleep 0.3` only because the app was mutating an `@Published` stat every
  second, re-rendering the whole settings pane (and refreshing its AX tree)
  whether or not anything had changed. Removing that per-second write for
  performance reasons dropped the test from 4/4 to 2/5 — the product was fine,
  the test had been leaning on an accidental refresh. See
  `docs/benchmarking.md`.
- The Settings window has, rarely and not reproducibly on demand,
  disappeared right after a synthetic Return keypress mid-edit. Cause
  unconfirmed (possibly cross-session interference — see below); a test
  that types into a field should tolerate it by re-opening Settings and
  retrying rather than failing outright.
- **Multiple worktrees/sessions share the bundle id** `com.lookaround.app`:
  another Claude session testing this repo in a different worktree runs
  its own `LookAround.app` under the same id, and `terminate`/`menu-click`
  will hit whichever instance macOS considers "the" running app —
  intermittent "no running app"/wrong-window failures during a test run
  are often that, not a real regression. Poll for no `LookAround.app`
  process before `terminate && launch` if failures look like cross-talk.

## If you outgrow this

If Xcode ever gets installed here, XCUITest remains the better long-term
choice (native assertions, `.xcresult` reports, CI integration, code
coverage) — see the "Full XCUITest" option considered and rejected for
this environment. It would slot in alongside `axdrive`, not replace the
`accessibilityIdentifier` work above, which both approaches share.
