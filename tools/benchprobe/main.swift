// benchprobe — sample a running process's resource counters, for benchmarking
// LookAround as a long-lived menu-bar resident (see docs/benchmarking.md).
//
// The counters come from `proc_pid_rusage` and `proc_pidinfo`, which the kernel
// exposes for same-user processes with no sudo, no entitlement and no Xcode —
// the same counters Activity Monitor's Energy tab is built on. That keeps the
// cheap tier of docs/benchmarking.md runnable anywhere, including CI runners
// without Xcode, where Instruments can't go and `powermetrics` needs root.
//
// `summarize` is the exception: it reads an XML export produced by `xctrace`,
// so it only comes into play once you've recorded a trace (scripts/profile.sh).
//
// Commands:
//   benchprobe sample    <pid>                    one raw counter snapshot
//   benchprobe quiesce   <pid> [--timeout SEC]    wait for startup to settle
//   benchprobe measure   <pid> [--window SEC]     steady-state rates over a window
//   benchprobe summarize <cpu-profile.xml>        rank a CPU profile by cycles

import Darwin
import Foundation

// MARK: - Counter snapshot

/// The subset of `rusage_info_v6` / `proc_taskinfo` worth tracking, already
/// converted out of mach units. Rates are computed by subtracting two of these.
struct Snapshot {
    var wallNs: UInt64
    var cpuNs: UInt64
    var idleWakeups: UInt64
    var interruptWakeups: UInt64
    var energyNj: UInt64
    var cycles: UInt64
    var pcoreCycles: UInt64
    var instructions: UInt64
    var diskReadBytes: UInt64
    var diskWriteBytes: UInt64
    var footprintBytes: UInt64
    var peakFootprintBytes: UInt64
    var threads: Int32
    var startAbsNs: UInt64
}

/// mach_absolute_time ticks → nanoseconds. On Apple Silicon the timebase is
/// not 1:1, so `ri_*_abstime` values must go through this.
let timebase: mach_timebase_info_data_t = {
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    return tb
}()

func absToNs(_ abs: UInt64) -> UInt64 {
    abs * UInt64(timebase.numer) / UInt64(timebase.denom)
}

func nowNs() -> UInt64 { absToNs(mach_absolute_time()) }

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("benchprobe: " + msg + "\n").utf8))
    exit(1)
}

func snapshot(_ pid: pid_t) -> Snapshot {
    var ri = rusage_info_v6()
    let rc = withUnsafeMutablePointer(to: &ri) { p -> Int32 in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rp in
            proc_pid_rusage(pid, RUSAGE_INFO_V6, rp)
        }
    }
    guard rc == 0 else { die("proc_pid_rusage(\(pid)) failed — is the process alive and owned by you?") }

    var ti = proc_taskinfo()
    let tiSize = Int32(MemoryLayout<proc_taskinfo>.size)
    let got = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, tiSize)
    guard got == tiSize else { die("proc_pidinfo(\(pid)) failed") }

    return Snapshot(
        wallNs: nowNs(),
        // `ri_user_time`/`ri_system_time` are mach absolute-time ticks, NOT
        // nanoseconds, despite the names — on this M4 a tick is 41.667 ns, so
        // reading them raw under-reports CPU by ~42x. Verified against a
        // busy-loop control process: raw says 2.4% of a core, converted says
        // 99.2%, and the loop really does peg one core. scripts/bench.sh keeps
        // that control process as a self-check so this can't silently rot.
        cpuNs: absToNs(ri.ri_user_time + ri.ri_system_time),
        idleWakeups: ri.ri_pkg_idle_wkups,
        interruptWakeups: ri.ri_interrupt_wkups,
        energyNj: ri.ri_energy_nj,
        cycles: ri.ri_cycles,
        pcoreCycles: ri.ri_pcycles,
        instructions: ri.ri_instructions,
        diskReadBytes: ri.ri_diskio_bytesread,
        diskWriteBytes: ri.ri_diskio_byteswritten,
        footprintBytes: ri.ri_phys_footprint,
        peakFootprintBytes: ri.ri_lifetime_max_phys_footprint,
        threads: ti.pti_threadnum,
        startAbsNs: absToNs(ri.ri_proc_start_abstime)
    )
}

// MARK: - JSON output
//
// Hand-rolled rather than JSONEncoder so key order stays stable and floats are
// rounded to a fixed number of places — a benchmark's output gets diffed, and
// full float precision makes every run look like a change.

func jsonLine(_ pairs: [(String, String)]) -> String {
    "{" + pairs.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
}

func num(_ value: Double, _ places: Int) -> String {
    String(format: "%.\(places)f", value)
}

// MARK: - Argument parsing

var args = Array(CommandLine.arguments.dropFirst())

func flagValue(_ name: String, default def: Double) -> Double {
    guard let i = args.firstIndex(of: name) else { return def }
    guard i + 1 < args.count, let v = Double(args[i + 1]) else { die("\(name) needs a number") }
    args.removeSubrange(i...(i + 1))
    return v
}

let usage = """
usage: benchprobe <command> [args...]
  sample    <pid>                     one raw counter snapshot as JSON
  quiesce   <pid> [--timeout SEC]     wait for startup to settle, report launch ms
  measure   <pid> [--window SEC]      steady-state rates over a window
  summarize <cpu-profile.xml>         rank an xctrace CPU profile by cycles
"""

guard let command = args.first else { print(usage); exit(2) }
args.removeFirst()

// Flags are pulled out before the positional argument, so either order works.
let timeoutSec = flagValue("--timeout", default: 15)
let windowSec = flagValue("--window", default: 30)
let topN = Int(flagValue("--top", default: 20))

func requirePid() -> pid_t {
    guard let a = args.first, let p = pid_t(a) else { die("expected a pid\n\n" + usage) }
    return p
}

switch command {
case "sample":
    let pid = requirePid()
    let s = snapshot(pid)
    print(jsonLine([
        ("pid", "\(pid)"),
        ("threads", "\(s.threads)"),
        ("cpu_ns", "\(s.cpuNs)"),
        ("idle_wakeups", "\(s.idleWakeups)"),
        ("interrupt_wakeups", "\(s.interruptWakeups)"),
        ("energy_nj", "\(s.energyNj)"),
        ("footprint_bytes", "\(s.footprintBytes)"),
        ("peak_footprint_bytes", "\(s.peakFootprintBytes)"),
        ("age_ms", num(Double(s.wallNs - s.startAbsNs) / 1e6, 1)),
    ]))

case "quiesce":
    let pid = requirePid()
    // "Launched" is a slippery thing to measure for a menu-bar app: there is no
    // first frame to time, and dyld4 dropped DYLD_PRINT_STATISTICS. What we can
    // time precisely is when the process *stops* doing startup work — poll the
    // CPU counter and wait for it to go flat. The clock starts at the kernel's
    // own record of exec (`ri_proc_start_abstime`), so it includes dyld and
    // everything before main(), and is independent of how the shell spawned us.
    let pollNs: UInt64 = 50_000_000       // 50 ms
    let quietFraction = 0.03              // <3% of a core counts as idle
    let neededQuietPolls = 10             // 500 ms of calm before we believe it
    // Startup is not one continuous burst of work — there are lulls while the
    // process waits on the window server, and a short quiet window lands in one
    // of them and reports a nonsense sub-100ms launch. Requiring both a real
    // amount of startup CPU and half a second of calm rejects those lulls.
    let minStartupCpuNs: UInt64 = 20_000_000
    let deadline = nowNs() + UInt64(timeoutSec * 1e9)

    var previous = snapshot(pid)
    let startAbsNs = previous.startAbsNs
    var quietPolls = 0
    var quiescedAtNs: UInt64? = nil

    while nowNs() < deadline {
        usleep(useconds_t(pollNs / 1000))
        let current = snapshot(pid)
        let wallDelta = Double(current.wallNs - previous.wallNs)
        let cpuDelta = Double(current.cpuNs - previous.cpuNs)
        let startedUp = current.cpuNs >= minStartupCpuNs
        if startedUp && wallDelta > 0 && cpuDelta / wallDelta < quietFraction {
            quietPolls += 1
            if quietPolls >= neededQuietPolls {
                // Credit the *first* quiet poll, not the last, so the confirmation
                // window doesn't inflate the reported launch time.
                quiescedAtNs = current.wallNs - pollNs * UInt64(neededQuietPolls - 1)
                break
            }
        } else {
            quietPolls = 0
        }
        previous = current
    }

    guard let quiesced = quiescedAtNs else {
        die("process \(pid) never went idle within \(num(timeoutSec, 0))s — still busy?")
    }
    let final = snapshot(pid)
    print(jsonLine([
        ("pid", "\(pid)"),
        ("launch_to_idle_ms", num(Double(quiesced - startAbsNs) / 1e6, 1)),
        ("launch_cpu_ms", num(Double(final.cpuNs) / 1e6, 1)),
        // Deliberately not "threads": bench.sh pools every key it sees across
        // both this and `measure`'s output, and a duplicate key would silently
        // average the just-launched count with the steady-state one.
        ("launch_threads", "\(final.threads)"),
    ]))

case "measure":
    let pid = requirePid()
    let before = snapshot(pid)

    // Thread count has to be sampled, not read once at the end: libdispatch
    // grows a worker pool on demand and reaps it after it goes idle, so a
    // single instantaneous read of an idle app swings (observed 12/6/6 across
    // three identical runs). The high-water mark over the window is both far
    // more stable and closer to what someone actually sees in Activity Monitor.
    var threadsMax = before.threads
    var threadsMin = before.threads
    var threadsSum = 0.0
    var threadSamples = 0.0
    let threadPollNs: UInt64 = 250_000_000
    let windowEnd = nowNs() + UInt64(windowSec * 1e9)
    while nowNs() < windowEnd {
        usleep(useconds_t(threadPollNs / 1000))
        let t = snapshot(pid).threads
        threadsMax = max(threadsMax, t)
        threadsMin = min(threadsMin, t)
        threadsSum += Double(t)
        threadSamples += 1
    }

    let after = snapshot(pid)

    let wallSec = Double(after.wallNs - before.wallNs) / 1e9
    guard wallSec > 0 else { die("zero-length window") }
    let perMin = 60.0 / wallSec

    func delta(_ keyPath: KeyPath<Snapshot, UInt64>) -> Double {
        // Counters are monotonic, but clamp anyway: a pid reused mid-window
        // would otherwise underflow into a nonsense number.
        let a = after[keyPath: keyPath], b = before[keyPath: keyPath]
        return a >= b ? Double(a - b) : 0
    }

    let cpuNs = delta(\.cpuNs)
    let cycles = delta(\.cycles)
    let pcore = delta(\.pcoreCycles)

    print(jsonLine([
        ("pid", "\(pid)"),
        ("window_sec", num(wallSec, 2)),
        // The headline number for a resident app: how much CPU it burns just
        // sitting there. Expressed per minute because percentages this small
        // round to zero and stop being comparable.
        ("cpu_ms_per_min", num(cpuNs / 1e6 * perMin, 2)),
        ("cpu_percent", num(cpuNs / (wallSec * 1e9) * 100, 4)),
        // Wakeups are what actually drains a battery for a timer-driven app —
        // a process can look like 0% CPU and still keep the SoC out of its
        // deep idle states.
        ("idle_wakeups_per_min", num(delta(\.idleWakeups) * perMin, 1)),
        ("interrupt_wakeups_per_min", num(delta(\.interruptWakeups) * perMin, 1)),
        ("energy_mj_per_min", num(delta(\.energyNj) / 1e6 * perMin, 2)),
        // A background app that lands on P-cores costs far more energy per unit
        // of work than one the scheduler can keep on E-cores.
        ("pcore_cycle_percent", num(cycles > 0 ? pcore / cycles * 100 : 0, 1)),
        ("instructions_per_min", num(delta(\.instructions) * perMin, 0)),
        ("disk_read_kb_per_min", num(delta(\.diskReadBytes) / 1024 * perMin, 1)),
        ("disk_write_kb_per_min", num(delta(\.diskWriteBytes) / 1024 * perMin, 1)),
        ("footprint_mb", num(Double(after.footprintBytes) / 1_048_576, 2)),
        ("peak_footprint_mb", num(Double(after.peakFootprintBytes) / 1_048_576, 2)),
        ("threads_max", "\(threadsMax)"),
        ("threads_min", "\(threadsMin)"),
        ("threads_mean", num(threadSamples > 0 ? threadsSum / threadSamples : Double(after.threads), 1)),
    ]))

case "summarize":
    // Turns `xctrace export --xpath …table[@schema="cpu-profile"]` into an
    // answer to "what is the app doing while it's supposed to be doing
    // nothing?". bench.sh tells you idle CPU moved; this tells you which stack
    // moved it.
    guard let path = args.first else { die("expected a path to an exported cpu-profile XML\n\n" + usage) }
    guard let doc = try? XMLDocument(contentsOf: URL(fileURLWithPath: path)) else {
        die("could not parse \(path) — is it an `xctrace export` XML?")
    }

    // The export interns repeated values: the first occurrence carries id="N"
    // and every later one is <tag ref="N"/>. Resolve by walking id-bearing
    // elements once up front.
    var byID: [String: XMLElement] = [:]
    if let all = try? doc.nodes(forXPath: "//*[@id]") {
        for case let e as XMLElement in all {
            if let id = e.attribute(forName: "id")?.stringValue { byID[id] = e }
        }
    }
    func resolve(_ parent: XMLElement, _ tag: String) -> XMLElement? {
        guard let e = parent.elements(forName: tag).first else { return nil }
        if let ref = e.attribute(forName: "ref")?.stringValue { return byID[ref] }
        return e
    }
    func fmt(_ e: XMLElement?) -> String { e?.attribute(forName: "fmt")?.stringValue ?? "?" }

    struct Bucket { var cycles: Double = 0; var samples: Int = 0 }
    var byLeaf: [String: Bucket] = [:]
    var byThread: [String: Bucket] = [:]
    var byState: [String: Bucket] = [:]
    var pCoreCycles = 0.0, eCoreCycles = 0.0, totalCycles = 0.0, totalSamples = 0

    let rows = (try? doc.nodes(forXPath: "//row")) ?? []
    for case let row as XMLElement in rows {
        let weight = Double(resolve(row, "cycle-weight")?.stringValue ?? "") ?? 0
        let thread = fmt(resolve(row, "thread"))
        let core = fmt(resolve(row, "core"))
        let state = fmt(resolve(row, "thread-state"))

        // Frames are listed innermost-first, so the first named frame is the leaf.
        var leaf = "(no backtrace)"
        if let bt = resolve(row, "tagged-backtrace"),
           let inner = bt.elements(forName: "backtrace").first,
           let frame = inner.elements(forName: "frame").first {
            let symbol = frame.attribute(forName: "name")?.stringValue ?? "?"
            let binary = frame.elements(forName: "binary").first.flatMap {
                $0.attribute(forName: "ref")?.stringValue.flatMap { r in byID[r] } ?? $0
            }
            let image = binary?.attribute(forName: "name")?.stringValue ?? "?"
            leaf = "\(image)  \(symbol)"
        }

        byLeaf[leaf, default: Bucket()].cycles += weight
        byLeaf[leaf, default: Bucket()].samples += 1
        byThread[thread, default: Bucket()].cycles += weight
        byThread[thread, default: Bucket()].samples += 1
        byState[state, default: Bucket()].cycles += weight
        byState[state, default: Bucket()].samples += 1
        if core.contains("P Core") { pCoreCycles += weight } else if core.contains("E Core") { eCoreCycles += weight }
        totalCycles += weight
        totalSamples += 1
    }

    guard totalSamples > 0 else { die("no samples in \(path)") }

    func report(_ title: String, _ buckets: [String: Bucket], limit: Int) {
        print("\n\(title)")
        print(String(repeating: "─", count: 78))
        for (name, b) in buckets.sorted(by: { $0.value.cycles > $1.value.cycles }).prefix(limit) {
            printf_row(name, b.cycles, b.samples)
        }
    }
    func printf_row(_ name: String, _ cycles: Double, _ samples: Int) {
        let pct = totalCycles > 0 ? cycles / totalCycles * 100 : 0
        let shown = name.count > 56 ? String(name.prefix(53)) + "…" : name
        print(String(format: "  %6.2f%%  %6d smp  %@", pct, samples, shown))
    }

    print("CPU profile: \(totalSamples) samples, \(num(totalCycles / 1e6, 1))M cycles")
    print(String(format: "P-cores %.1f%%   E-cores %.1f%%",
                 totalCycles > 0 ? pCoreCycles / totalCycles * 100 : 0,
                 totalCycles > 0 ? eCoreCycles / totalCycles * 100 : 0))
    report("By thread", byThread, limit: 12)
    report("By thread state", byState, limit: 6)
    report("Top \(topN) leaf frames", byLeaf, limit: topN)

default:
    die("unknown command '\(command)'\n\n" + usage)
}
