import SwiftUI
import AppKit

@main
struct LookAroundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = SettingsStore()
    @StateObject private var scheduler: BreakScheduler

    init() {
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

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(scheduler)
        }
    }
}

/// Compact menu-bar label: eye icon + live countdown.
struct MenuBarLabel: View {
    @EnvironmentObject var scheduler: BreakScheduler
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scheduler.isOnBreak ? "cup.and.saucer.fill" : "eye.fill")
            if scheduler.isOnBreak {
                Text(TimeFmt.mmss(scheduler.session?.remaining ?? 0))
                    .monospacedDigit()
            } else if scheduler.manuallyPaused {
                Image(systemName: "pause.fill")
            } else if let t = scheduler.timeUntilNextBreak {
                Text(TimeFmt.mmss(t))
                    .monospacedDigit()
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock-less menu-bar utility app, like the original.
        NSApp.setActivationPolicy(.accessory)
    }
}
