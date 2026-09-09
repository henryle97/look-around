# Benchmarking LookAround

How people benchmark macOS apps, which of it applies to a menu-bar resident,
and the two tools this repo ships as a result.

## What matters for *this* app

LookAround is not a throughput app. Nobody cares how many breaks per second it
can schedule. It is a process that sits in the menu bar for eight hours doing
almost nothing, so the questions worth asking are:

- What does it cost to **do nothing**? (idle CPU, wakeups, energy)
- Does it **grow** over a workday? (memory footprint, thread count)
- Does it get in the way at **launch**?
- How big is the download?

That framing rules out most of the standard Swift benchmarking stack.
Microbenchmark harnesses like [swift-benchmark] and [package-benchmark] measure
throughput and allocations of a *function* — excellent tools, wrong unit of
analysis. Our costs are emergent properties of a whole running process: a timer
firing, SwiftUI recomputing, a framework parking a thread.

[swift-benchmark]: https://www.swift.org/blog/benchmarks/
[package-benchmark]: https://github.com/ordo-one/package-benchmark

## The standard macOS toolbox, and what we can use

| Tool | Gives you | Verdict here |
|---|---|---|
| **Instruments** (Time Profiler, Allocations, Leaks, Power) | Rich, symbolicated, the reference answer | Yes — via `xctrace`, see tier 2 |
| **`xctrace`** (Instruments CLI) | Scriptable recording + XML export | Yes — tier 2 |
| **`powermetrics`** | Per-process energy impact, wakeups | No — requires root, awkward in a script |
| **`footprint` / `vmmap` / `leaks` / `heap`** | Memory detail, leak detection | Occasionally, by hand |
| **`top` / `ps`** | Cheap, always available | Too coarse: `ps` CPU time is centiseconds |
| **`proc_pid_rusage`** | ns CPU, wakeups, energy, footprint, cycles | **Yes — the basis of tier 1** |
| **XCTest `measure`** | Baseline-tracked perf tests | No — this repo has no Xcode project |
| **`DYLD_PRINT_STATISTICS`** | Pre-`main()` launch breakdown | No — removed in dyld4 |
| **MetricKit** | Field data from real users | No — iOS-oriented, and we ship no telemetry |

The load-bearing discovery is `proc_pid_rusage`. The kernel will hand any
same-user process a struct containing nanosecond CPU time, idle and interrupt
wakeup counts, energy in nanojoules, physical footprint, disk I/O and
instruction/cycle counts — **no root, no entitlement, no Xcode**. These are the
same counters Activity Monitor's Energy tab is built on. That makes a real
benchmark cheap enough to run on every change and on a CI box with no Xcode.

## Two tiers

Benchmarking splits into two jobs that want different tools, and conflating
them is why perf work often stalls.

**Tier 1 — the gate: `./scripts/bench.sh`**
Cheap, repeatable, no Xcode. Answers *did anything get worse?* Run it on a
change; run it in CI. Roughly 100× cheaper than recording a trace.

**Tier 2 — the diagnosis: `./scripts/profile.sh`**
Records an Instruments trace and ranks it. Answers *why did it get worse?* Needs
a full Xcode. Run it when tier 1 flags something, or when you want to know where
idle CPU actually goes.

### Tier 1: `scripts/bench.sh`

```
./scripts/bench.sh                                   # measure, print a table
./scripts/bench.sh --json bench.json                 # save machine-readable
./scripts/bench.sh --baseline bench.json             # compare, exit 1 on regression
./scripts/bench.sh --reps 5 --window 60              # tighter numbers, slower
```

Each rep launches a fresh copy of *this worktree's* app, waits for startup to
finish, lets it settle, then samples counters over a window. Reps are reduced by
**median**, not mean — launch timing has a long right tail and one unlucky rep
should not decide anything.

The regression gate uses **per-metric tolerances**, because these metrics are
not equally noisy. Peak thread count is the steadiest and gets 10% (enough for
the one-thread pool wobble, not enough to hide a real jump); energy is the
noisiest and gets 40%. `idle_wakeups_per_min`, `pcore_cycle_percent` and the disk
counters are reported but deliberately **not** gated — see the caveats below.

### Tier 2: `scripts/profile.sh`

```
./scripts/profile.sh                                 # 20s of steady-state idle
./scripts/profile.sh --duration 60 --top 40          # longer, deeper
./scripts/profile.sh --template Allocations          # a different instrument
./scripts/profile.sh --keep out.trace                # keep it for the GUI
```

By default it **attaches after the app has settled**, because a trace that
includes launch is dominated by dyld and says nothing about steady-state cost.
It exports the `cpu-profile` table and ranks it by thread, thread state and leaf
frame (`benchprobe summarize` does the ranking, so you get an answer in the
terminal rather than a `.trace` to open by hand).

## Traps found while building this

These are all things that produced confidently wrong numbers before being
caught. They are the reason the scripts look more defensive than you might
expect.

**`ri_user_time` is not nanoseconds.** Despite the name, `rusage_info`'s CPU
fields are in mach absolute-time ticks — 41.667 ns each on an M4. Reading them
raw under-reports CPU by ~42×, and the result still looks plausible (0.03%
instead of 1.3%), so nothing tips you off. `bench.sh` therefore measures a
known 100%-CPU process on every run as a self-check and refuses to report if
that control does not read ~100%.

**`xctrace --launch` may profile the wrong build.** It takes a binary path but
hands it to LaunchServices, which resolves it to whichever copy of the bundle is
*registered*. Passing this worktree's binary silently profiled
`/Applications/LookAround.app` — a different build with a different SHA.
`profile.sh` now reads the traced process path back out of the trace and
refuses if it is not from this worktree. Attach mode is immune.

**Thread count is not a single number.** libdispatch grows a worker pool on
demand and reaps it when idle, so one instantaneous read of an idle app swings
(12 / 6 / 6 across three identical runs). `benchprobe measure` samples threads
every 250 ms across the window and reports peak, mean and min. The peak is far
steadier than a spot reading — but not exact either: identical builds have
measured 11 / 12 / 11, so the gate allows a one-thread wobble.

**Other test runs kill your app mid-measurement.** `axdrive terminate` kills by
bundle id, so any other agent or worktree running the UI suite takes your copy
down. `bench.sh` refuses to start if a LookAround from outside this worktree is
running, kills only the PIDs it started, and retries a rep whose app dies.

**Measure after settling, not from launch.** A window that starts at launch
reported 56 MB/min of disk reads; the same app measured after settling reports
0. Those were startup page-ins. `bench.sh` waits for quiescence and then a
settle period before it starts counting.

**`idle_wakeups` is environment-dependent.** `ri_pkg_idle_wkups` counts only
wakeups that actually pulled the SoC out of idle, so it collapses toward zero on
a busy machine (observed 0 → 102 /min for identical builds). Informative on a
quiet laptop, useless as a CI gate.

## Baseline on an M4 MacBook Pro (macOS 26.5)

Median of 3 reps, 20 s window, app idle, no break in progress:

| Metric | Value |
|---|---|
| idle CPU | ~1.0–1.3 % (≈600–800 ms/min) |
| interrupt wakeups | ~400 /min |
| memory footprint | ~19.5 MB |
| threads (peak) | 11 |
| launch → idle | ~1.2 s |
| bundle / binary | 5.62 MB / 3.50 MB |

Numbers are machine- and load-specific. Record your own baseline before
comparing; do not treat this table as a target.

## Findings

**Idle CPU is ~1%, and it is nearly all one thread.** Tier 2 attributes 99.9% of
idle samples to the main thread, and the top frames are `SwiftUI`/`AttributeGraph`
view-graph work, `CoreAutoLayout` constraint solving, and — consistently —
`Foundation JSONWriter.serializeString`.

**The app used to re-encode all of its settings to JSON once per second while
idle — fixed, but it was not the main cost.** `BreakScheduler.tick()` accrued
screen time straight into `@Published` stats every tick, tripping
`SettingsStore`'s debounced autosave, which encoded the *entire* settings
snapshot and wrote it to `UserDefaults`. Screen time is now buffered in a
private counter and flushed once a minute (and on day rollover and app quit).

`JSONWriter.serializeString` is gone from the idle profile, confirming the fix
lands. **Idle CPU did not measurably improve**: 1.285% → 1.262%, well inside the
+-0.15pp run-to-run spread the same build shows. That is consistent rather than
disappointing — JSON encoding was only ~2.5% of idle samples, so the predicted
saving was ~0.03pp all along, below what this method can resolve. The change is
still worth keeping: it removes a `UserDefaults` write every second, forever.

**The real idle cost is the per-second menu-bar redraw.** With JSON gone, the
profile is `SwiftUICore` / `AttributeGraph::propagate_dirty` /
`NSView _recursive:displayRect...` / `QuartzCore` — the countdown label
republishing every tick and dragging a SwiftUI invalidation and an AppKit draw
behind it. Anyone chasing the remaining ~1.2% should start by not redrawing the
label while the popover is closed and the minute has not changed. That is a
behaviour change, so it is left alone here.

## Verdict on the thread-count change on this branch

The branch makes `BreakScheduler.calendarMonitor` `lazy` and gates it behind
`CalendarMonitor.isAuthorized`, so an unauthorized app never constructs an
`EKEventStore`. Measured over 8 launches per side on a machine where calendar
access is `notDetermined`:

```
pre-fix   threads(peak):  11 12 11 11 11 11 11 11
with-fix  threads(peak):  11 11 11 11 11 11 11 11
```

The change is directionally right and costs nothing, but the effect is **one
occasional thread, not one persistent thread**. The doc comment on
`isAuthorized` claims building an `EKEventStore` "parks worker threads for the
life of the process" — that is not what this machine shows, where the threads
are transient and get reaped. Either soften the comment, or re-measure on a Mac
with calendar access actually granted, which is the case the claim most likely
came from. Idle CPU also moved (1.35% → 1.00–1.16%) but across runs that sits
inside the noise band; do not claim it without more reps.

## Adding a metric

`tools/benchprobe/main.swift` — add the field to `Snapshot`, populate it in
`snapshot()`, emit it from `measure`. Anything in `rusage_info_v6` or
`proc_taskinfo` is available. `bench.sh` picks up new JSON keys automatically
for the median; add a row to the table and, if it is stable enough to gate on,
an entry to the `tol[]` table.

Two rules that are easy to get wrong:

- **Do not reuse a key name across `quiesce` and `measure`.** `bench.sh` pools
  every key it sees, so a duplicate silently averages two different things.
  This is why launch reports `launch_threads`, not `threads`.
- **The comparison block in `bench.sh` is a single-quoted awk program.** An
  apostrophe in a comment inside it terminates the quote and breaks the script.
