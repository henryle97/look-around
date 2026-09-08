#!/bin/zsh
# Benchmark LookAround as a long-lived menu-bar resident: what does it cost to
# just sit there? See docs/benchmarking.md for why these metrics and not others.
#
# Each repetition launches a fresh copy of *this worktree's* app, times how long
# it takes to stop doing startup work, lets it settle, then samples kernel
# resource counters over a window. Repetitions are reduced by median, because
# one unlucky run on a busy laptop shouldn't decide whether a change regressed.
#
#   ./scripts/bench.sh                                  measure, print a table
#   ./scripts/bench.sh --json bench.json                also write machine-readable
#   ./scripts/bench.sh --baseline bench.json            compare, fail on regression
#
set -uo pipefail
cd "$(dirname "$0")/.."

REPO="$(pwd)"
APP="$REPO/LookAround.app"
BIN="$APP/Contents/MacOS/LookAround"
PROBE="$REPO/tools/benchprobe/benchprobe"

REPS=3
WINDOW=30
SETTLE=15
JSON_OUT=""
BASELINE=""
NO_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reps)     REPS="$2"; shift 2 ;;
        --window)   WINDOW="$2"; shift 2 ;;
        --settle)   SETTLE="$2"; shift 2 ;;
        --json)     JSON_OUT="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        --no-build) NO_BUILD=1; shift ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

WORK="$(mktemp -d)"
SAMPLES="$WORK/samples.jsonl"
: > "$SAMPLES"

# Kill only the PIDs we started. The usual `axdrive terminate` kills by bundle
# id, which would also take down a copy of LookAround running from the main
# checkout or another worktree — and, worse, another agent's run would take down
# ours mid-window. Same no-strays guarantee, narrower blast radius.
OUR_PIDS=()
cleanup() {
    for p in ${OUR_PIDS[@]:-}; do kill "$p" 2>/dev/null; done
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

log() { echo "→ $*"; }

# ---------------------------------------------------------------- build

if [[ $NO_BUILD -eq 0 ]]; then
    log "building app + benchprobe…"
    ./build.sh >/dev/null || { echo "✗ build failed" >&2; exit 1; }
    ./tools/benchprobe/build.sh >/dev/null || { echo "✗ benchprobe build failed" >&2; exit 1; }
fi
[[ -x "$BIN" ]]   || { echo "✗ missing $BIN" >&2; exit 1; }
[[ -x "$PROBE" ]] || { echo "✗ missing $PROBE" >&2; exit 1; }

# ------------------------------------------------- environment sanity checks

# A copy running from somewhere else competes for the same singleton resources
# (status item, UserDefaults domain) and skews every number below.
FOREIGN="$(pgrep -f 'LookAround\.app/Contents/MacOS/LookAround' 2>/dev/null \
           | while read -r p; do
                 path="$(ps -o command= -p "$p" 2>/dev/null)"
                 [[ "$path" == "$REPO"* ]] || echo "$p"
             done)"
if [[ -n "$FOREIGN" ]]; then
    echo "✗ another LookAround is running outside this worktree (pids: $(echo $FOREIGN))" >&2
    ps -o pid,command= -p $(echo "$FOREIGN" | tr '\n' ',' | sed 's/,$//') >&2
    echo "  Benchmarking against a contended machine gives numbers you can't trust." >&2
    echo "  Quit it (or wait for the other test run to finish) and retry." >&2
    exit 1
fi

# benchprobe converts mach ticks to nanoseconds by hand; if that ever silently
# breaks, every CPU number below becomes wrong by ~42x while still looking
# plausible. A process that pegs exactly one core is a cheap ground truth.
log "self-check: measuring a known 100%-CPU process…"
nohup /bin/sh -c 'while :; do :; done' >/dev/null 2>&1 & disown
CONTROL=$!
sleep 0.3
CONTROL_CPU="$("$PROBE" measure "$CONTROL" --window 3 \
    | sed -n 's/.*"cpu_percent":\([0-9.]*\).*/\1/p')"
kill "$CONTROL" 2>/dev/null
if ! awk -v v="${CONTROL_CPU:-0}" 'BEGIN { exit !(v > 85 && v < 115) }'; then
    echo "✗ self-check failed: a 100%-CPU process measured ${CONTROL_CPU:-?}%" >&2
    echo "  benchprobe's CPU accounting is wrong — do not trust these results." >&2
    exit 1
fi
echo "  ✓ control process read ${CONTROL_CPU}% (expected ~100%)"

# ---------------------------------------------------------------- measure

BUNDLE_MB="$(awk -v b="$(du -sk "$APP" | cut -f1)" 'BEGIN { printf "%.2f", b/1024 }')"
BINARY_MB="$(awk -v b="$(stat -f%z "$BIN")" 'BEGIN { printf "%.2f", b/1048576 }')"

log "running $REPS reps (settle ${SETTLE}s, window ${WINDOW}s) — about $(( REPS * (SETTLE + WINDOW + 3) ))s"
for i in $(seq 1 "$REPS"); do
    # A rep can be lost through no fault of the build: `axdrive terminate` kills
    # by bundle id, so any other test run on this machine takes our copy down
    # mid-window. That is an environment failure, not a measurement, so retry
    # rather than aborting a run that is minutes deep.
    launch=""; steady=""
    for attempt in 1 2 3; do
        # --ui-testing keeps the run hermetic: no update check, no network.
        nohup "$BIN" --ui-testing >/dev/null 2>&1 & disown
        pid=$!
        OUR_PIDS+=("$pid")

        if ! launch="$("$PROBE" quiesce "$pid" --timeout 20 2>/dev/null)"; then
            kill "$pid" 2>/dev/null; sleep 1; continue
        fi
        sleep "$SETTLE"
        if ! steady="$("$PROBE" measure "$pid" --window "$WINDOW" 2>/dev/null)"; then
            echo "  rep $i attempt $attempt: app died mid-window (killed by another test run?) — retrying" >&2
            kill "$pid" 2>/dev/null; sleep 1; continue
        fi
        break
    done
    if [[ -z "$steady" ]]; then
        echo "✗ rep $i failed three times — is something else launching/killing LookAround?" >&2
        exit 1
    fi

    echo "$launch $steady" >> "$SAMPLES"
    printf '  rep %d/%d  cpu=%s%%  threads=%s  footprint=%sMB  launch=%sms\n' "$i" "$REPS" \
        "$(echo "$steady" | sed -n 's/.*"cpu_percent":\([0-9.]*\).*/\1/p')" \
        "$(echo "$steady" | sed -n 's/.*"threads_max":\([0-9]*\).*/\1/p')" \
        "$(echo "$steady" | sed -n 's/.*"footprint_mb":\([0-9.]*\).*/\1/p')" \
        "$(echo "$launch" | sed -n 's/.*"launch_to_idle_ms":\([0-9.]*\).*/\1/p')"

    kill "$pid" 2>/dev/null
    sleep 0.5
done

# ---------------------------------------------------------------- aggregate
#
# Median rather than mean: launch timings in particular have a long right tail
# (a stray Spotlight index run inflates one rep and nothing else).

MEDIANS="$WORK/medians.txt"
awk '
function median(name,   n, i, j, tmp, arr) {
    n = count[name]
    for (i = 0; i < n; i++) arr[i] = vals[name, i]
    for (i = 1; i < n; i++) {          # insertion sort; macOS awk has no asort
        tmp = arr[i]
        for (j = i - 1; j >= 0 && arr[j] > tmp; j--) arr[j + 1] = arr[j]
        arr[j + 1] = tmp
    }
    if (n == 0) return 0
    return (n % 2) ? arr[int(n / 2)] : (arr[n / 2 - 1] + arr[n / 2]) / 2
}
{
    # Flat, known-shape JSON: split on the punctuation and read key/value pairs.
    gsub(/[{}"]/, "")
    n = split($0, parts, /[ ,]+/)
    for (i = 1; i <= n; i++) {
        split(parts[i], kv, ":")
        k = kv[1]; v = kv[2]
        if (k == "pid" || k == "" || v !~ /^-?[0-9.]+$/) continue
        vals[k, count[k]++] = v + 0
        seen[k] = 1
    }
}
END { for (k in seen) printf "%s %.4f\n", k, median(k) }
' "$SAMPLES" | sort > "$MEDIANS"

# Build artefacts aren't sampled per-rep, but they belong in the same table and
# in the regression gate — a binary that doubles in size is a regression too.
printf 'bundle_mb %s\nbinary_mb %s\n' "$BUNDLE_MB" "$BINARY_MB" >> "$MEDIANS"

get() { awk -v k="$1" '$1 == k { print $2 }' "$MEDIANS"; }
fmt() { awk -v v="$(get "$1")" -v p="${2:-2}" 'BEGIN { printf "%.*f", p, v }'; }

echo ""
echo "LookAround — idle menu-bar cost   (median of $REPS reps, ${WINDOW}s window)"
echo "────────────────────────────────────────────────────────────────"
printf '  %-28s %10s %s\n' "idle CPU"            "$(fmt cpu_percent 3)"     "%"
printf '  %-28s %10s %s\n' "idle CPU"            "$(fmt cpu_ms_per_min 1)"  "ms/min"
printf '  %-28s %10s %s\n' "idle wakeups"        "$(fmt idle_wakeups_per_min 1)" "/min"
printf '  %-28s %10s %s\n' "interrupt wakeups"   "$(fmt interrupt_wakeups_per_min 1)" "/min"
printf '  %-28s %10s %s\n' "energy"              "$(fmt energy_mj_per_min 1)" "mJ/min"
printf '  %-28s %10s %s\n' "work on P-cores"     "$(fmt pcore_cycle_percent 1)" "%"
printf '  %-28s %10s %s\n' "memory footprint"    "$(fmt footprint_mb 2)"    "MB"
printf '  %-28s %10s %s\n' "peak footprint"      "$(fmt peak_footprint_mb 2)" "MB"
printf '  %-28s %10s %s\n' "threads (peak)"      "$(fmt threads_max 0)"     ""
printf '  %-28s %10s %s\n' "threads (mean)"      "$(fmt threads_mean 1)"    ""
printf '  %-28s %10s %s\n' "disk read"           "$(fmt disk_read_kb_per_min 1)" "KB/min"
printf '  %-28s %10s %s\n' "disk write"          "$(fmt disk_write_kb_per_min 1)" "KB/min"
echo "────────────────────────────────────────────────────────────────"
printf '  %-28s %10s %s\n' "launch → idle"       "$(fmt launch_to_idle_ms 0)" "ms"
printf '  %-28s %10s %s\n' "launch CPU"          "$(fmt launch_cpu_ms 1)"   "ms"
printf '  %-28s %10s %s\n' "bundle size"         "$BUNDLE_MB"               "MB"
printf '  %-28s %10s %s\n' "binary size"         "$BINARY_MB"               "MB"
echo ""

# ---------------------------------------------------------------- emit

RESULT="$WORK/result.json"
{
    echo "{"
    # No "window_sec" here — the medians carry the *measured* window length,
    # and emitting the requested one too would duplicate the key.
    printf '  "reps": %s, "settle_sec": %s,\n' "$REPS" "$SETTLE"
    awk '{ printf "  \"%s\": %s,\n", $1, $2 }' "$MEDIANS" | sed '$ s/,$//'
    echo "}"
} > "$RESULT"

if [[ -n "$JSON_OUT" ]]; then
    cp "$RESULT" "$JSON_OUT"
    log "wrote $JSON_OUT"
fi

# ---------------------------------------------------------------- compare
#
# Per-metric tolerances, because these metrics are not equally noisy. Thread
# count is deterministic and gets no slack at all — it's the one number here
# that changes only when the code changes.

[[ -n "$BASELINE" ]] || exit 0
[[ -f "$BASELINE" ]] || { echo "✗ no such baseline: $BASELINE" >&2; exit 1; }

echo "vs baseline $BASELINE"
echo "────────────────────────────────────────────────────────────────"
awk -v base="$BASELINE" '
BEGIN {
    # Tolerances are per-metric because these numbers are not equally noisy.
    # Deliberately NOT gated: idle_wakeups_per_min (counts only wakeups that
    # actually pulled the SoC out of idle, so it collapses to near-zero on a
    # busy machine and is unusable as a gate), plus pcore_cycle_percent and the
    # disk counters for the same reason. They stay in the table because a human
    # reading one result finds them informative; a CI job cannot.
    # NOTE: no apostrophes anywhere in this awk program — it is single-quoted.
    tol["cpu_percent"]                = 30
    tol["cpu_ms_per_min"]             = 30
    tol["interrupt_wakeups_per_min"]  = 30
    tol["energy_mj_per_min"]          = 40
    tol["footprint_mb"]               = 15
    tol["peak_footprint_mb"]          = 15
    # Not zero: repeated runs of an *identical* build measured 11 / 12 / 11,
    # because libdispatch pool churn adds or drops a worker. 10% lets a
    # one-thread wobble through at this thread count while still catching a
    # real jump (11 to 13 is +18%).
    tol["threads_max"]                = 10
    tol["launch_to_idle_ms"]          = 40
    tol["binary_mb"]                  = 10

    while ((getline line < base) > 0) {
        gsub(/[{}",]/, "", line)
        split(line, kv, ":")
        k = kv[1]; gsub(/^[ \t]+|[ \t]+$/, "", k)
        if (k in tol) old[k] = kv[2] + 0
    }
    fail = 0
}
$1 in tol {
    k = $1; new = $2 + 0
    if (!(k in old)) next
    delta = new - old[k]
    pct = old[k] > 0 ? delta / old[k] * 100 : (delta != 0 ? 100 : 0)
    verdict = (pct > tol[k]) ? "REGRESSED" : (pct < -tol[k] ? "improved" : "ok")
    if (verdict == "REGRESSED") fail = 1
    printf "  %-26s %10.3f → %-10.3f %+7.1f%%  %s\n", k, old[k], new, pct, verdict
}
END {
    print "────────────────────────────────────────────────────────────────"
    if (fail) { print "✗ regression detected"; exit 1 }
    print "✓ no regression"
}
' "$MEDIANS"
