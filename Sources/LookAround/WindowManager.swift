import AppKit
import SwiftUI

/// Owns the fullscreen break overlay, heads-up panel, cursor-following
/// countdown pills and the Settings window.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var overlayWindows: [NSWindow] = []
    private var preBreakWindow: NSPanel?
    private var settingsWindow: NSWindow?
    private var floatingWindow: NSWindow?
    private var floatingKind: FloatingKind?
    private var floatTimer: Timer?
    private var escMonitor: Any?
    private var lastEscAt: Date?
    private weak var boundScheduler: BreakScheduler?

    enum FloatingKind { case countdown, overtime }

    // MARK: - break overlay (all screens, screen-saver level)
    func showBreakOverlay(scheduler: BreakScheduler, settings: SettingsStore) {
        if !overlayWindows.isEmpty { return }
        boundScheduler = scheduler
        for screen in NSScreen.screens {
            let view = BreakOverlayView()
                .environmentObject(scheduler)
                .environmentObject(settings)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = screen.frame
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered, defer: false, screen: screen
            )
            win.contentView = hosting
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.backgroundColor = .black
            win.isOpaque = false
            win.hasShadow = false
            win.ignoresMouseEvents = false
            win.isMovable = false
            win.orderFrontRegardless()
            win.makeKeyAndOrderFront(nil)
            overlayWindows.append(win)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Double-Esc on the break screen (no permissions needed: overlay is key).
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                Task { @MainActor in
                    let now = Date()
                    if let last = self.lastEscAt, now.timeIntervalSince(last) < 0.8 {
                        self.lastEscAt = nil
                        self.boundScheduler?.handleDoubleEscape()
                    } else {
                        self.lastEscAt = now
                    }
                }
            }
            return event
        }
    }

    func hideBreakOverlay() {
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows = []
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        lastEscAt = nil
    }

    // MARK: - pre-break heads-up
    func showPreBreak(scheduler: BreakScheduler, settings: SettingsStore) {
        if preBreakWindow == nil {
            let view = PreBreakView()
                .environmentObject(scheduler)
                .environmentObject(settings)
            let hosting = NSHostingView(rootView: view)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 392, height: 170),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            panel.contentView = hosting
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovable = true
            panel.becomesKeyOnlyIfNeeded = true
            preBreakWindow = panel
        }
        guard let panel = preBreakWindow, let screen = NSScreen.main else { return }
        let sw = screen.visibleFrame
        let w: CGFloat = 392
        let x: CGFloat
        switch settings.breaks.reminderPosition {
        case .topLeft: x = sw.minX + 16
        case .topCenter: x = sw.midX - w / 2
        case .topRight: x = sw.maxX - w - 16
        }
        panel.setFrameOrigin(NSPoint(x: x, y: sw.maxY - 186))
        panel.orderFrontRegardless()
    }

    func hidePreBreak() {
        preBreakWindow?.orderOut(nil)
    }

    // MARK: - settings window (own window: reliable in menu-bar-only apps)
    func openSettings(scheduler: BreakScheduler, settings: SettingsStore) {
        if let w = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
            .environmentObject(scheduler)
            .environmentObject(settings)
        let hosting = NSHostingView(rootView: view)
        let rect = NSRect(x: 0, y: 0, width: 1000, height: 720)
        hosting.frame = rect
        let win = NSWindow(contentRect: rect,
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.contentView = hosting
        win.center()
        win.title = "LookAround Settings"
        win.isReleasedWhenClosed = false
        win.delegate = self
        settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == settingsWindow {
            settingsWindow = nil
        }
    }

    // MARK: - floating pills (countdown / overtime) that follow the cursor

    /// Shows the countdown pill, the overtime pill, or nothing.
    func syncFloating(scheduler: BreakScheduler, settings: SettingsStore) {
        if scheduler.isOnBreak || scheduler.manuallyPaused && !settings.breaks.overtimeShowWhenPaused {
            if !scheduler.overtimeVisible { hideFloatingCountdown(); return }
        }
        if scheduler.overtimeVisible {
            showFloating(kind: .overtime, scheduler: scheduler, settings: settings)
        } else if scheduler.countdownVisible {
            showFloating(kind: .countdown, scheduler: scheduler, settings: settings)
        } else {
            hideFloatingCountdown()
        }
    }

    // MARK: - floating countdown that follows the cursor
    private func showFloating(kind: FloatingKind, scheduler: BreakScheduler, settings: SettingsStore) {
        if floatingKind != kind || floatingWindow == nil {
            floatingKind = kind
            let view: AnyView
            switch kind {
            case .countdown:
                view = AnyView(FloatingCountdownView().environmentObject(scheduler))
            case .overtime:
                view = AnyView(OvertimePillView().environmentObject(scheduler))
            }
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 60)
            if floatingWindow == nil {
                let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
                win.level = .floating
                win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                win.backgroundColor = .clear
                win.isOpaque = false
                win.hasShadow = false
                win.ignoresMouseEvents = true
                floatingWindow = win
            }
            floatingWindow?.contentView = hosting
        }
        floatingWindow?.orderFrontRegardless()
        if floatTimer == nil {
            floatTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.repositionFloating() }
            }
        }
    }

    private func repositionFloating() {
        guard let win = floatingWindow else { return }
        let mouse = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: mouse.x + 18, y: mouse.y - 42))
    }

    private func hideFloatingCountdown() {
        floatTimer?.invalidate()
        floatTimer = nil
        floatingKind = nil
        floatingWindow?.orderOut(nil)
    }
}
