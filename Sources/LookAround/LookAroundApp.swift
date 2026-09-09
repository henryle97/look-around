import SwiftUI
import AppKit
import Combine

/// Dev/test-mode switches for agent-driven UI testing (see AGENTS.md).
/// Checked once at launch, before any state is loaded — never compiled out,
/// so a Release build can still be exercised deterministically by a driver.
enum UITesting {
    /// `--ui-testing` launch argument or `LOOKAROUND_UI_TESTING=1` env var.
    static let isEnabled: Bool = {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.environment["LOOKAROUND_UI_TESTING"] == "1"
    }()

    /// `--reset-state` launch argument: wipes persisted settings before
    /// `SettingsStore` loads, so every launch starts from known defaults.
    static let shouldResetState: Bool =
        ProcessInfo.processInfo.arguments.contains("--reset-state")

    static func resetStateIfRequested() {
        guard shouldResetState else { return }
        UserDefaults.standard.removeObject(forKey: SettingsStore.persistenceKey)
    }
}

@main
struct LookAroundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        UITesting.resetStateIfRequested()
        let s = SettingsStore()
        Shared.settings = s
        Shared.scheduler = BreakScheduler(settings: s)
        Shared.updateChecker = UpdateChecker()
        // NOTE: no NSApp access here — it is nil during App struct init.
        // Dock-less menu-bar behavior comes from LSUIElement in Info.plist,
        // enforced again in AppDelegate on launch.
    }

    var body: some Scene {
        // The menu-bar item is a classic NSStatusItem owned by the app
        // delegate (see StatusBarController) — this bare Settings scene
        // just keeps the accessory app legal without adding windows.
        Settings { EmptyView() }
    }
}

/// Shared engine, created once in App.init (after the UI-testing reset)
/// and consumed by the AppDelegate-owned status item.
enum Shared {
    static var settings: SettingsStore!
    static var scheduler: BreakScheduler!
    static var updateChecker: UpdateChecker!
}

/// Compact menu-bar label: eye icon + live countdown.
/// Hosted in a real NSHostingView inside the status-item button (see
/// StatusBarController), so the centered HStack lands the eye on the
/// digits' optical center with no nudges — verified from captures
/// (both ink centers row 15). Do NOT add .offset here; the earlier
/// misalignment came from MenuBarExtra's button layout, not this stack.
struct MenuBarLabel: View {
    @EnvironmentObject var scheduler: BreakScheduler
    var body: some View {
        Group {
            if scheduler.isOnBreak {
                statusLabel(icon: "cup.and.saucer.fill",
                            text: TimeFmt.mmss(scheduler.session?.remaining ?? 0))
            } else if scheduler.manuallyPaused {
                Image(systemName: "pause.fill")
            } else if let t = scheduler.timeUntilNextBreak {
                statusLabel(icon: "eye.fill", text: TimeFmt.mmss(t))
            } else {
                Image(systemName: "eye.fill")
            }
        }
        .onChange(of: scheduler.isOnBreak) { onBreak in
            if onBreak {
                // Scheduler is @MainActor; hop there explicitly.
                Task { @MainActor in
                    WindowManager.shared.hidePreBreak()
                    // settings access via scheduler
                    WindowManager.shared.showBreakOverlay(
                        scheduler: scheduler, settings: scheduler.settings)
                    WindowManager.shared.syncFloating(
                        scheduler: scheduler, settings: scheduler.settings)
                }
            } else {
                Task { @MainActor in
                    WindowManager.shared.hideBreakOverlay()
                    WindowManager.shared.syncFloating(
                        scheduler: scheduler, settings: scheduler.settings)
                }
            }
        }
        .onChange(of: scheduler.preBreakVisible) { visible in
            Task { @MainActor in
                if visible && !scheduler.isOnBreak {
                    WindowManager.shared.showPreBreak(
                        scheduler: scheduler, settings: scheduler.settings)
                } else {
                    WindowManager.shared.hidePreBreak()
                }
            }
        }
        .onChange(of: scheduler.countdownVisible) { _ in
            Task { @MainActor in
                WindowManager.shared.syncFloating(
                    scheduler: scheduler, settings: scheduler.settings)
            }
        }
        .onChange(of: scheduler.overtimeVisible) { _ in
            Task { @MainActor in
                WindowManager.shared.syncFloating(
                    scheduler: scheduler, settings: scheduler.settings)
            }
        }
    }

    private func statusLabel(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 13))
                .monospacedDigit()
        }
    }
}

/// Classic NSStatusItem + NSPopover in place of MenuBarExtra.
///
/// Why not MenuBarExtra: its label is decomposed into an NSStatusBarButton
/// image + title, so view-level layout (.font size, .offset,
/// .alignmentGuide) is silently discarded — verified with a 26pt-font
/// build that rendered at system size. A real NSHostingView inside the
/// button honors layout, so the eye/countdown pair can be pixel-aligned.
final class StatusBarController: NSObject {
    private var item: NSStatusItem?
    private var labelHost: NSView?
    private let popover = NSPopover()
    private var tick: AnyCancellable?

    func setup(scheduler: BreakScheduler, settings: SettingsStore) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item

        let host = NSHostingView(rootView: MenuBarLabel().environmentObject(scheduler))
        host.translatesAutoresizingMaskIntoConstraints = false
        self.labelHost = host
        if let button = item.button {
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(scheduler)
                .environmentObject(settings)
                .environmentObject(Shared.updateChecker))
        popover.behavior = .transient

        // Icon swaps (eye/pause/cup) change the label width — track it.
        // (The countdown itself is monospaced, so per-second ticks are free.)
        tick = scheduler.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncLength() }
        }
        syncLength()
    }

    private func syncLength() {
        guard let item, let host = labelHost else { return }
        let w = max(24, host.fittingSize.width)
        if abs(item.length - w) > 0.5 { item.length = w }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bar = StatusBarController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock-less menu-bar utility app, like the original.
        NSApp.setActivationPolicy(.accessory)
        bar.setup(scheduler: Shared.scheduler, settings: Shared.settings)
        // UI tests stub out network access with --reset-state/--ui-testing
        // runs that don't need real update checks; skip hitting GitHub then.
        if !UITesting.isEnabled {
            Shared.updateChecker.start(settings: Shared.settings)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Screen time is buffered in the scheduler and the autosave is debounced,
        // so a quit would otherwise drop both. Flush and write synchronously.
        Shared.scheduler?.flushScreenTime()
        Shared.settings?.save()
    }
}
