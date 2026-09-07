import SwiftUI
import AppKit

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
    @StateObject private var settings = SettingsStore()
    @StateObject private var scheduler: BreakScheduler

    init() {
        UITesting.resetStateIfRequested()
        let s = SettingsStore()
        _settings = StateObject(wrappedValue: s)
        _scheduler = StateObject(wrappedValue: BreakScheduler(settings: s))
        // NOTE: no NSApp access here — it is nil during App struct init.
        // Dock-less menu-bar behavior comes from LSUIElement in Info.plist,
        // enforced again in AppDelegate on launch.
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(scheduler)
                .environmentObject(settings)
        } label: {
            MenuBarLabel()
                .environmentObject(scheduler)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Compact menu-bar label: eye icon + live countdown.
/// Uses Label (not a bare HStack) so the symbol stays optically centered
/// on the countdown text instead of drifting off-baseline.
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
        Label {
            Text(text).monospacedDigit()
        } icon: {
            Image(systemName: icon)
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock-less menu-bar utility app, like the original.
        NSApp.setActivationPolicy(.accessory)
    }
}
