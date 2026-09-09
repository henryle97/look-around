#!/bin/zsh
# Deep-dive profiler: record an Instruments trace of LookAround and rank it.
#
# This is the second tier of docs/benchmarking.md. scripts/bench.sh tells you
# *that* idle CPU (or memory, or thread count) moved; this tells you *which
# code* moved it. It needs a full Xcode install for `xctrace` — bench.sh
# deliberately does not, so the regression gate still runs on a bare CI box.
#
# By default it attaches only after the app has finished launching, because a
# trace that includes startup is dominated by dyld and tells you nothing about
# steady-state cost.
#
#   ./scripts/profile.sh                        profile 20s of idle
#   ./scripts/profile.sh --duration 60          longer sample
#   ./scripts/profile.sh --template Allocations pick another instrument
#   ./scripts/profile.sh --launch               include app startup instead
#
set -uo pipefail
cd "$(dirname "$0")/.."

REPO="$(pwd)"
BIN="$REPO/LookAround.app/Contents/MacOS/LookAround"
PROBE="$REPO/tools/benchprobe/benchprobe"

TEMPLATE="CPU Profiler"
DURATION=20
SETTLE=10
TOP=25
INCLUDE_LAUNCH=0
KEEP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --template) TEMPLATE="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --settle)   SETTLE="$2"; shift 2 ;;
        --top)      TOP="$2"; shift 2 ;;
        --launch)   INCLUDE_LAUNCH=1; shift ;;
        --keep)     KEEP="$2"; shift 2 ;;
        -h|--help)  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

command -v xctrace >/dev/null 2>&1 || { echo "✗ xctrace not found" >&2; exit 1; }
if ! xctrace version >/dev/null 2>&1; then
    echo "✗ xctrace needs a full Xcode, not just Command Line Tools." >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    echo "  (scripts/bench.sh works without Xcode if you just need the numbers.)" >&2
    exit 1
fi

WORK="$(mktemp -d)"
TRACE="$WORK/lookaround.trace"
APP_PID=""
cleanup() {
    [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null
    if [[ -n "$KEEP" && -d "$TRACE" ]]; then
        rm -rf "$KEEP"; cp -R "$TRACE" "$KEEP"
        echo "→ trace kept at $KEEP  (open it with: open '$KEEP')"
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

echo "→ building…"
./build.sh >/dev/null || { echo "✗ build failed" >&2; exit 1; }
./tools/benchprobe/build.sh >/dev/null || { echo "✗ benchprobe build failed" >&2; exit 1; }

if [[ $INCLUDE_LAUNCH -eq 1 ]]; then
    echo "→ recording '$TEMPLATE' for ${DURATION}s, including launch…"
    xctrace record --template "$TEMPLATE" --output "$TRACE" \
        --time-limit "${DURATION}s" --launch -- "$BIN" --ui-testing >/dev/null 2>&1
else
    nohup "$BIN" --ui-testing >/dev/null 2>&1 & disown
    APP_PID=$!
    "$PROBE" quiesce "$APP_PID" --timeout 20 >/dev/null || { echo "✗ app never settled" >&2; exit 1; }
    echo "→ app settled (pid $APP_PID); letting it idle ${SETTLE}s…"
    sleep "$SETTLE"
    echo "→ recording '$TEMPLATE' for ${DURATION}s of steady-state idle…"
    xctrace record --template "$TEMPLATE" --output "$TRACE" \
        --time-limit "${DURATION}s" --attach "$APP_PID" >/dev/null 2>&1
fi
[[ -d "$TRACE" ]] || { echo "✗ xctrace produced no trace" >&2; exit 1; }

# `xctrace --launch` takes a path but hands it to LaunchServices, which resolves
# it to whichever copy of the bundle is *registered* — so passing this
# worktree's binary can silently profile /Applications/LookAround.app instead.
# Verified: the two binaries had different SHAs and the trace named the
# installed one. Always confirm which build we actually measured.
TRACED_PATH="$(xctrace export --input "$TRACE" --toc 2>/dev/null \
    | sed -n 's/.*<process[^>]*name="LookAround"[^>]*path="\([^"]*\)".*/\1/p' | head -1)"
if [[ -n "$TRACED_PATH" && "$TRACED_PATH" != "$REPO"* ]]; then
    echo "✗ xctrace profiled the wrong build: $TRACED_PATH" >&2
    echo "  LaunchServices redirected to a registered copy of the bundle." >&2
    echo "  Use the default (attach) mode, which profiles the process we started." >&2
    exit 1
fi

# Only the CPU-sampling templates produce a cpu-profile table we can rank; for
# anything else, hand the user the trace and let Instruments render it.
XML="$WORK/cpu-profile.xml"
if xctrace export --input "$TRACE" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="cpu-profile"]' \
      > "$XML" 2>/dev/null && [[ -s "$XML" ]]; then
    "$PROBE" summarize "$XML" --top "$TOP"
else
    echo "→ '$TEMPLATE' has no cpu-profile table to rank."
    [[ -z "$KEEP" ]] && KEEP="$REPO/lookaround.trace"
fi

echo ""
[[ -n "$KEEP" ]] || echo "  (re-run with --keep out.trace to open the full trace in Instruments)"
