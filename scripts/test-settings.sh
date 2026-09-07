#!/bin/zsh
# E2E: full settings tour — every sidebar page opens, one screenshot per
# page lands in /tmp/lookaround-screens, representative edits across six
# feature areas persist across a restart, and the automation add-flow works.
# See AGENTS.md. Never leaves the app running.
set -uo pipefail
cd "$(dirname "$0")/.."

APP="$(pwd)/LookAround.app"
BUNDLE_ID="com.lookaround.app"
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
assert_ne() {
    local got="$1" want="$2" what="$3"
    if [[ "$got" == "$want" ]]; then
        echo "✗ FAIL: $what — value never changed ('$got')"; FAIL=1
    else
        echo "✓ $what changed '$want' → '$got'"
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
# One always-present element per page, used to assert the page rendered.
# (Page-root identifiers are deliberately NOT used: stamping a custom View
# subtree overrides the descendants' own identifiers — see AGENTS.md.)
sentinel_for() {
    case "$1" in
        general)         echo "settings.general.launchAtLogin";;
        screenBreaks)    echo "settings.screenBreaks.breakDuration";;
        smartPause)      echo "settings.smartPause.meetings";;
        wellness)        echo "settings.wellness.postureInterval";;
        stats)           echo "settings.stats.skipped";;
        alerts)          echo "settings.alerts.countdownDuration";;
        lockScreen)      echo "settings.lock.showStatus";;
        sounds)          echo "settings.sounds.volume";;
        shortcuts)       echo "settings.shortcuts.openAXSettings";;
        iphoneSync)      echo "settings.iphoneSync.status";;
        automation)      echo "settings.automation.addScript";;
        about)           echo "settings.about.version";;
        customizeScreen) echo "settings.customize.gradient.0";;
        longBreaks)      echo "settings.longBreaks.duration";;
        plannedBreaks)   echo "settings.plannedBreaks.addButton";;
        officeHours)     echo "settings.officeHours.enabled";;
        editPlanned)     echo "settings.plannedBreak.startTime";;
    esac
}
goto_page() {
    "$AX" click "$BUNDLE_ID" "settings.nav.$1" >/dev/null
    wait_for "$(sentinel_for "$1")" || { echo "✗ FAIL: page $1 never appeared"; FAIL=1; return 1; }
}
# Sub-pages live behind in-page rows on Screen Breaks, not the sidebar.
goto_subpage() {
    goto_page screenBreaks || return 1
    "$AX" click "$BUNDLE_ID" "settings.nav.$1" >/dev/null
    wait_for "$(sentinel_for "$1")" || { echo "✗ FAIL: sub-page $1 never appeared"; FAIL=1; return 1; }
}
shot() { "$AX" shot-window "$BUNDLE_ID" "LookAround Settings" "$SHOTS/$1.png" >/dev/null; }
shot_popup() {
    # The popover auto-dismisses when the app deactivates (e.g. a system
    # notification banner) — make sure it is open before capturing.
    wait_for "menubar.settingsButton" 5 || open_popover || return 1
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

SIDEBAR_PAGES=(general screenBreaks smartPause wellness stats alerts lockScreen
                 sounds shortcuts iphoneSync automation about)
# Sub-pages reachable only through in-page rows on Screen Breaks.
# NOTE: customMessages has no UI entry point (dead route) — excluded.
SUB_PAGES=(customizeScreen longBreaks plannedBreaks officeHours)

log "building app + axdrive…"
./build.sh >/dev/null
./tools/axdrive/build.sh >/dev/null
mkdir -p "$SHOTS"

log "launching with --ui-testing --reset-state…"
launch_app --ui-testing --reset-state
open_settings || exit 1

log "capturing menu-bar popup (Now + Stats tabs)…"
open_popover || exit 1
shot_popup "01-popup-now"
echo "  stats line: $("$AX" read "$BUNDLE_ID" menubar.statsLine)"
"$AX" click "$BUNDLE_ID" menubar.tab.stats >/dev/null
sleep 0.3
shot_popup "02-popup-stats"
open_settings || exit 1

log "touring all settings pages…"
i=3
for slug in "${SIDEBAR_PAGES[@]}"; do
    goto_page "$slug" || exit 1
    shot "$(printf '%02d-page-%s' "$i" "$slug")"
    i=$((i + 1))
done
goto_page screenBreaks || exit 1
for slug in "${SUB_PAGES[@]}"; do
    "$AX" click "$BUNDLE_ID" "settings.nav.$slug" >/dev/null
    wait_for "$(sentinel_for "$slug")" || { echo "✗ FAIL: sub-page $slug never appeared"; exit 1; }
    shot "$(printf '%02d-page-%s' "$i" "$slug")"
    i=$((i + 1))
    goto_page screenBreaks || exit 1
done
echo "✓ all $(( ${#SIDEBAR_PAGES[@]} + ${#SUB_PAGES[@]} )) reachable pages opened"

log "reaching the planned-break editor…"
goto_subpage plannedBreaks || exit 1
"$AX" click "$BUNDLE_ID" settings.plannedBreaks.addButton >/dev/null
wait_for "$(sentinel_for editPlanned)" || { echo "✗ FAIL: editor never appeared"; exit 1; }
shot "$(printf '%02d-page-editPlanned' "$i")"
echo "✓ editor page opened"

log "editing one control per feature area…"
goto_page screenBreaks
snooze_before="$("$AX" read "$BUNDLE_ID" settings.screenBreaks.snoozesPerDay.value)"
"$AX" increment "$BUNDLE_ID" settings.screenBreaks.snoozesPerDay 2 >/dev/null
snooze_after="$("$AX" read "$BUNDLE_ID" settings.screenBreaks.snoozesPerDay.value)"
assert_ne "$snooze_after" "$snooze_before" "snoozes per day"

goto_subpage longBreaks
long_before="$("$AX" read "$BUNDLE_ID" settings.longBreaks.duration.value)"
"$AX" increment "$BUNDLE_ID" settings.longBreaks.duration 1 >/dev/null
long_after="$("$AX" read "$BUNDLE_ID" settings.longBreaks.duration.value)"
assert_ne "$long_after" "$long_before" "long break duration"

goto_page smartPause
meet_before="$("$AX" read "$BUNDLE_ID" settings.smartPause.meetings)"
"$AX" click "$BUNDLE_ID" settings.smartPause.meetings >/dev/null
sleep 0.2
meet_after="$("$AX" read "$BUNDLE_ID" settings.smartPause.meetings)"
assert_ne "$meet_after" "$meet_before" "smart-pause meetings toggle"

goto_subpage officeHours
oh_before="$("$AX" read "$BUNDLE_ID" settings.officeHours.enabled)"
"$AX" click "$BUNDLE_ID" settings.officeHours.enabled >/dev/null
sleep 0.2
oh_after="$("$AX" read "$BUNDLE_ID" settings.officeHours.enabled)"
assert_ne "$oh_after" "$oh_before" "office-hours toggle"

goto_page wellness
post_before="$("$AX" read "$BUNDLE_ID" settings.wellness.postureInterval.value)"
"$AX" increment "$BUNDLE_ID" settings.wellness.postureInterval 1 >/dev/null
post_after="$("$AX" read "$BUNDLE_ID" settings.wellness.postureInterval.value)"
assert_ne "$post_after" "$post_before" "posture interval"

goto_page alerts
cd_before="$("$AX" read "$BUNDLE_ID" settings.alerts.countdownDuration.value)"
"$AX" increment "$BUNDLE_ID" settings.alerts.countdownDuration 1 >/dev/null
cd_after="$("$AX" read "$BUNDLE_ID" settings.alerts.countdownDuration.value)"
assert_ne "$cd_after" "$cd_before" "countdown duration"

log "adding an automation (default 'New script')…"
goto_page automation
"$AX" click "$BUNDLE_ID" settings.automation.addScript >/dev/null
wait_for "settings.automation.nameField" || { echo "✗ FAIL: automation editor never appeared"; exit 1; }
shot "$(printf '%02d-automation-editor' "$i")"
"$AX" click "$BUNDLE_ID" settings.automation.doneButton >/dev/null
wait_for "settings.automation.row.New script" || { echo "✗ FAIL: new automation row never appeared"; exit 1; }
echo "✓ automation row appeared"

log "waiting for autosave, restarting, re-verifying…"
sleep 0.6
launch_app --ui-testing
open_settings || exit 1
goto_page screenBreaks
assert_eq "$("$AX" read "$BUNDLE_ID" settings.screenBreaks.snoozesPerDay.value)" "$snooze_after" "snoozes persist"
goto_subpage longBreaks
assert_eq "$("$AX" read "$BUNDLE_ID" settings.longBreaks.duration.value)" "$long_after" "long duration persists"
goto_page smartPause
assert_eq "$("$AX" read "$BUNDLE_ID" settings.smartPause.meetings)" "$meet_after" "meetings toggle persists"
goto_subpage officeHours
assert_eq "$("$AX" read "$BUNDLE_ID" settings.officeHours.enabled)" "$oh_after" "office-hours toggle persists"
goto_page wellness
assert_eq "$("$AX" read "$BUNDLE_ID" settings.wellness.postureInterval.value)" "$post_after" "posture interval persists"
goto_page alerts
assert_eq "$("$AX" read "$BUNDLE_ID" settings.alerts.countdownDuration.value)" "$cd_after" "countdown persists"
goto_page automation
if wait_for "settings.automation.row.New script" 10; then
    echo "✓ automation persists"
else
    echo "✗ FAIL: automation row lost after restart"; FAIL=1
fi

log "resetting to defaults…"
launch_app --ui-testing --reset-state
"$AX" terminate "$BUNDLE_ID" >/dev/null 2>&1

if [[ "$FAIL" -eq 0 ]]; then echo "✓ all checks passed"; else echo "✗ one or more checks failed"; fi
exit "$FAIL"
