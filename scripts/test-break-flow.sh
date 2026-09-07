#!/bin/zsh
# E2E: break lifecycle — start a short break from the menu bar, screenshot
# the fullscreen overlay, skip it, confirm the overlay is gone and the
# Stats page counted the skip; then confirm a long break overlay appears
# and the Quit button quits cleanly. See AGENTS.md.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="$(pwd)/LookAround.app"
BUNDLE_ID="com.lookaround.app"
# NOTE: there is deliberately no `break.overlay` root identifier — stamping
# a custom View subtree overrides the descendants' own ids (see AGENTS.md).
# The Skip pill existing == the overlay is up (default difficulty).
OVERLAY_SENTINEL="break.skipButton"
AX="./tools/axdrive/axdrive"
SHOTS="/tmp/lookaround-screens"
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
wait_gone() {
    local identifier="$1" tries="${2:-20}"
    for _ in $(seq 1 "$tries"); do
        if ! "$AX" find "$BUNDLE_ID" "$identifier" >/dev/null 2>&1; then return 0; fi
        sleep 0.25
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
shot() {
    "$AX" shot-display 1 "$SHOTS/$1-d1.png" >/dev/null
    "$AX" shot-display 2 "$SHOTS/$1-d2.png" >/dev/null
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
mkdir -p "$SHOTS"

log "launching fresh…"
launch_app --ui-testing --reset-state

log "starting a short break from the menu bar…"
open_popover || { echo "✗ FAIL: popover never opened"; exit 1; }
"$AX" click "$BUNDLE_ID" menubar.startShortBreak >/dev/null
wait_for "$OVERLAY_SENTINEL" 15 || { echo "✗ FAIL: break overlay never appeared"; exit 1; }
echo "✓ overlay appeared"
sleep 0.5
shot "30-break-overlay"

log "waiting out the skip delay, then skipping…"
sleep 6
"$AX" click "$BUNDLE_ID" break.skipButton >/dev/null
wait_gone "$OVERLAY_SENTINEL" || { echo "✗ FAIL: overlay still present after skip"; exit 1; }
echo "✓ overlay dismissed by skip"
shot "31-after-skip"

log "confirming Stats counted the skip…"
sleep 0.6
open_popover || exit 1
"$AX" click "$BUNDLE_ID" menubar.settingsButton >/dev/null
wait_for "settings.nav.stats" || exit 1
"$AX" click "$BUNDLE_ID" settings.nav.stats >/dev/null
wait_for "settings.stats.skipped" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.stats.skipped)" "1" "skipped counter"

log "starting a long break (overlay must appear)…"
open_popover || exit 1
"$AX" click "$BUNDLE_ID" menubar.startLongBreak >/dev/null
wait_for "$OVERLAY_SENTINEL" 15 || { echo "✗ FAIL: long-break overlay never appeared"; exit 1; }
echo "✓ long-break overlay appeared"
shot "32-break-overlay-long"

log "relaunching to test the Quit button…"
launch_app --ui-testing
open_popover || exit 1
# NOTE: pressing Quit usually reports `press failed: -25204` — the AX
# reply round-trip dies with the app even though the action lands. So a
# press error is fine as long as the process is actually gone.
"$AX" click "$BUNDLE_ID" menubar.quitButton >/dev/null 2>&1
sleep 1.5
if pgrep -x LookAround >/dev/null; then
    echo "✗ FAIL: app still running after Quit"; FAIL=1
    "$AX" terminate "$BUNDLE_ID" >/dev/null 2>&1
else
    echo "✓ Quit button terminated the app"
fi

if [[ "$FAIL" -eq 0 ]]; then echo "✓ all checks passed"; else echo "✗ one or more checks failed"; fi
exit "$FAIL"
