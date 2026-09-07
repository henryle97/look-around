#!/bin/zsh
# End-to-end UI test for LookAround, driven via axdrive (Accessibility API)
# instead of XCUITest — see AGENTS.md for why, and tools/axdrive for the
# driver itself. No Xcode required, matches build.sh's CLT-only toolchain.
#
# Scenario ("break duration persists"): open Settings → Screen Breaks,
# bump the break-duration stepper, restart the app, confirm the new value
# survived; then confirm --reset-state wipes it back to the default.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="$(pwd)/LookAround.app"
BUNDLE_ID="com.lookaround.app"
AX="./tools/axdrive/axdrive"
FAIL=0

log() { echo "→ $*"; }
assert_eq() {
    local got="$1" want="$2" what="$3"
    if [[ "$got" != "$want" ]]; then
        echo "✗ FAIL: $what — got '$got', want '$want'"
        FAIL=1
    else
        echo "✓ $what == '$got'"
    fi
}

# Poll `axdrive find` until the identifier resolves or the timeout elapses.
wait_for() {
    local identifier="$1" tries="${2:-20}"
    for _ in $(seq 1 "$tries"); do
        if "$AX" find "$BUNDLE_ID" "$identifier" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.15
    done
    return 1
}

# Opening the MenuBarExtra popover is occasionally a no-op on the very
# first click right after launch (timing race with app startup) — retry.
open_popover() {
    for _ in 1 2 3; do
        "$AX" menu-click "$BUNDLE_ID" >/dev/null 2>&1
        if wait_for "menubar.settingsButton" 8; then return 0; fi
    done
    return 1
}

open_screen_breaks_settings() {
    open_popover || { echo "✗ FAIL: could not open the menu-bar popover"; FAIL=1; return 1; }
    "$AX" click "$BUNDLE_ID" menubar.settingsButton >/dev/null
    wait_for "settings.nav.screenBreaks" || { echo "✗ FAIL: Settings window never appeared"; FAIL=1; return 1; }
    "$AX" click "$BUNDLE_ID" settings.nav.screenBreaks >/dev/null
    wait_for "settings.screenBreaks.breakDuration.value"
}

launch_app() {
    "$AX" terminate "$BUNDLE_ID" >/dev/null 2>&1
    sleep 0.3
    local args=(launch "$APP")
    for a in "$@"; do args+=(--arg "$a"); done
    "$AX" "${args[@]}" >/dev/null
    sleep 1
}

log "building app + axdrive…"
./build.sh >/dev/null
./tools/axdrive/build.sh >/dev/null

log "launching with --ui-testing --reset-state…"
launch_app --ui-testing --reset-state
open_screen_breaks_settings || exit 1

before="$("$AX" read "$BUNDLE_ID" settings.screenBreaks.breakDuration.value)"
assert_eq "$before" "20 seconds" "default break duration"

log "bumping break duration by 3 steps (5s each)…"
"$AX" increment "$BUNDLE_ID" settings.screenBreaks.breakDuration 3 >/dev/null
sleep 0.2
after="$("$AX" read "$BUNDLE_ID" settings.screenBreaks.breakDuration.value)"
assert_eq "$after" "35 seconds" "break duration after +3"

log "waiting for debounced autosave, then restarting the app…"
sleep 0.6
launch_app --ui-testing
open_screen_breaks_settings || exit 1
persisted="$("$AX" read "$BUNDLE_ID" settings.screenBreaks.breakDuration.value)"
assert_eq "$persisted" "35 seconds" "break duration survives restart"

log "relaunching with --reset-state to confirm it wipes the value…"
launch_app --ui-testing --reset-state
open_screen_breaks_settings || exit 1
reset="$("$AX" read "$BUNDLE_ID" settings.screenBreaks.breakDuration.value)"
assert_eq "$reset" "20 seconds" "break duration after --reset-state"

"$AX" terminate "$BUNDLE_ID" >/dev/null 2>&1

if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ all checks passed"
else
    echo "✗ one or more checks failed"
fi
exit "$FAIL"
