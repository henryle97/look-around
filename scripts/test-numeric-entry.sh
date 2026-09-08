#!/bin/zsh
# E2E: direct numeric entry on stepper chips (EditableHMBox / ChipStepper,
# see SettingsView.swift) — click the number to type it instead of only
# clicking the up/down arrows. Covers a plain-unit box (work-duration H/M),
# a pure-integer ChipStepper (snoozes/day), a seconds-stored/minutes-shown
# ChipStepper (break duration) including its unit-conversion and clamping,
# persistence across a restart, and that time-of-day fields (office hours)
# were deliberately left stepper-only. See docs/ui-testing.md.
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
        echo "✗ FAIL: $what — got '$got', want '$want'"; FAIL=1
    else
        echo "✓ $what == '$got'"
    fi
}
wait_for() {
    local identifier="$1" tries="${2:-20}"
    for _ in $(seq 1 "$tries"); do
        if "$AX" find "$BUNDLE_ID" "$identifier" >/dev/null 2>&1; then return 0; fi
        sleep 0.15
    done
    return 1
}
open_popover() {
    for _ in 1 2 3; do
        "$AX" menu-click "$BUNDLE_ID" >/dev/null 2>&1
        if wait_for "menubar.settingsButton" 8; then return 0; fi
    done
    return 1
}
open_screen_breaks() {
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
# Click a value chip, clear whatever it currently shows (TextFields select
# their whole contents on focus, so one backspace already clears it — over-
# clearing by a few more is a harmless no-op) and type new digits.
# Synthetic keystrokes occasionally don't land (a CGEvent/focus race, not a
# product bug — see docs/ui-testing.md), so retry the whole click-type-enter
# round trip a few times before asserting.
type_and_verify() {
    local id="$1" digits="$2" want="$3" what="$4"
    local got=""
    for _ in 1 2 3; do
        # The Settings window has occasionally been observed to vanish
        # after a synthetic Return keypress (not reproducible on demand —
        # possibly cross-session interference on the shared bundle id, see
        # docs/ui-testing.md); reopen it before each attempt so a retry
        # can actually make progress instead of clicking into nothing.
        wait_for "settings.screenBreaks.breakDuration.value" 3 || open_screen_breaks >/dev/null
        "$AX" click "$BUNDLE_ID" "$id" >/dev/null 2>&1
        sleep 0.35
        "$AX" type "$BUNDLE_ID" "$digits" --clear=6 --enter >/dev/null 2>&1
        # Poll for the committed value instead of sleeping a fixed amount. The
        # settings pane only re-renders when something actually changes, so
        # there is no single delay that is both quick and safe — this used to
        # pass on a fixed 0.3s only because the app happened to mutate a
        # @Published stat every second, re-rendering (and refreshing the AX
        # tree) whether or not anything had changed. That is gone; see
        # docs/benchmarking.md.
        for _ in $(seq 1 15); do
            got="$("$AX" read "$BUNDLE_ID" "$id" 2>/dev/null)"
            [[ "$got" == "$want" ]] && break
            sleep 0.1
        done
        [[ "$got" == "$want" ]] && break
    done
    assert_eq "$got" "$want" "$what"
}

log "building app + axdrive…"
./build.sh >/dev/null
./tools/axdrive/build.sh >/dev/null

log "launching with --ui-testing --reset-state…"
launch_app --ui-testing --reset-state
open_screen_breaks || exit 1

log "default work-duration H/M…"
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.workHours.value)" "0" "default work hours"
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.workMinutes.value)" "10" "default work minutes"

log "typing into the work-duration H/M boxes…"
type_and_verify settings.screenBreaks.workMinutes.value 45 "45" "work minutes after typing 45"
type_and_verify settings.screenBreaks.workHours.value 3 "3" "work hours after typing 3"

log "typing into a pure-integer ChipStepper (snoozes/day, range 0-20)…"
type_and_verify settings.screenBreaks.snoozesPerDay.value 12 "12" "snoozes/day after typing 12"
log "  …and confirming it clamps to the range…"
type_and_verify settings.screenBreaks.snoozesPerDay.value 99 "20" "snoozes/day clamps to max (20)"

log "typing into a seconds-stored/minutes-shown ChipStepper (break duration)…"
type_and_verify settings.screenBreaks.breakDuration.value 45 "45 seconds" "break duration after typing 45 (seconds mode)"
type_and_verify settings.screenBreaks.breakDuration.value 300 "5 minutes" "break duration after typing 300 (seconds mode → minutes display)"
log "  …re-clicking now edits in minutes (matches the display)…"
type_and_verify settings.screenBreaks.breakDuration.value 999 "10 minutes" "break duration clamps to max (600s = 10 minutes) when typed in minutes mode"

log "confirming office-hours start/end stayed stepper-only (no click-to-edit)…"
"$AX" click "$BUNDLE_ID" settings.nav.officeHours >/dev/null
wait_for "settings.officeHours.enabled" || { echo "✗ FAIL: office-hours page never appeared"; FAIL=1; }
oh_enabled="$("$AX" read "$BUNDLE_ID" settings.officeHours.enabled)"
if [[ "$oh_enabled" != "1" ]]; then "$AX" click "$BUNDLE_ID" settings.officeHours.enabled >/dev/null; sleep 0.3; fi
if "$AX" tree "$BUNDLE_ID" 2>/dev/null | grep -q "AXTextField"; then
    echo "✗ FAIL: an office-hours time chip is click-to-edit — it should still be stepper-only"; FAIL=1
else
    echo "✓ office-hours time chips have no editable text field"
fi

log "waiting for debounced autosave, then restarting the app…"
sleep 0.6
launch_app --ui-testing
open_screen_breaks || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.workHours.value)" "3" "work hours survive restart"
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.workMinutes.value)" "45" "work minutes survive restart"
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.snoozesPerDay.value)" "20" "snoozes/day survive restart"
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.breakDuration.value)" "10 minutes" "break duration survives restart"

log "relaunching with --reset-state to confirm it wipes typed values…"
launch_app --ui-testing --reset-state
open_screen_breaks || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.workMinutes.value)" "10" "work minutes reset to default"
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.breakDuration.value)" "20 seconds" "break duration reset to default"

"$AX" terminate "$BUNDLE_ID" >/dev/null 2>&1
if [[ "$FAIL" -eq 0 ]]; then echo "✓ all checks passed"; else echo "✗ one or more checks failed"; fi
exit "$FAIL"
