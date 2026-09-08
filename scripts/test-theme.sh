#!/bin/zsh
# E2E: theme plan — AppTheme (System/Dark/Light) + BreakMaterial
# (Frosted/Liquid Glass) pickers persist across a restart, and
# --reset-state wipes them back to defaults. See docs/theme-plan.md.
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
open_settings() {
    open_popover || { echo "✗ FAIL: could not open the menu-bar popover"; FAIL=1; return 1; }
    "$AX" click "$BUNDLE_ID" menubar.settingsButton >/dev/null
    wait_for "settings.window" || { echo "✗ FAIL: Settings window never appeared"; FAIL=1; return 1; }
}
goto_page() {
    "$AX" click "$BUNDLE_ID" "settings.nav.$1" >/dev/null
    wait_for "$2" || { echo "✗ FAIL: page $1 never appeared"; FAIL=1; return 1; }
}
goto_subpage() {
    goto_page screenBreaks "settings.screenBreaks.breakDuration" || return 1
    "$AX" click "$BUNDLE_ID" "settings.nav.$1" >/dev/null
    wait_for "$2" || { echo "✗ FAIL: sub-page $1 never appeared"; FAIL=1; return 1; }
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
open_settings || exit 1

log "checking theme defaults…"
goto_page general "settings.general.launchAtLogin" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.general.appTheme.value)" "System" "default app theme"
goto_subpage customizeScreen "settings.customize.background.mode.wallpaper" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.customizeScreen.material.value)" "Frosted" "default break material"

log "setting Light + Liquid Glass…"
goto_page general "settings.general.launchAtLogin" || exit 1
"$AX" click "$BUNDLE_ID" settings.general.appTheme.light >/dev/null
sleep 0.2
assert_eq "$("$AX" read "$BUNDLE_ID" settings.general.appTheme.value)" "Light" "app theme after click"
goto_subpage customizeScreen "settings.customize.background.mode.wallpaper" || exit 1
"$AX" click "$BUNDLE_ID" settings.customizeScreen.material.liquidGlass >/dev/null
sleep 0.2
assert_eq "$("$AX" read "$BUNDLE_ID" settings.customizeScreen.material.value)" "Liquid Glass" "material after click"

log "waiting for autosave, restarting, re-verifying…"
sleep 0.6
launch_app --ui-testing
open_settings || exit 1
goto_page general "settings.general.launchAtLogin" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.general.appTheme.value)" "Light" "app theme persists"
goto_subpage customizeScreen "settings.customize.background.mode.wallpaper" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.customizeScreen.material.value)" "Liquid Glass" "material persists"

log "relaunching with --reset-state to confirm defaults return…"
launch_app --ui-testing --reset-state
open_settings || exit 1
goto_page general "settings.general.launchAtLogin" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.general.appTheme.value)" "System" "app theme after --reset-state"
goto_subpage customizeScreen "settings.customize.background.mode.wallpaper" || exit 1
assert_eq "$("$AX" read "$BUNDLE_ID" settings.customizeScreen.material.value)" "Frosted" "material after --reset-state"

"$AX" terminate "$BUNDLE_ID" >/dev/null 2>&1

if [[ "$FAIL" -eq 0 ]]; then echo "✓ all checks passed"; else echo "✗ one or more checks failed"; fi
exit "$FAIL"
