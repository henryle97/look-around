// axdrive — a tiny Accessibility (AX) driver for agent-driven UI testing of
// LookAround, used in place of XCUITest because this repo is CLT-only (no
// Xcode / xcodebuild installed). See AGENTS.md for the testing loop this
// is meant to sit inside.
//
// It walks the target app's accessibility tree looking for elements whose
// AXIdentifier matches the `.accessibilityIdentifier(...)` values set in
// the SwiftUI views (see Sources/LookAround/SettingsView.swift and friends),
// then performs actions on them (press / increment / decrement / read).
//
// Build:  swiftc -O -o tools/axdrive/axdrive tools/axdrive/main.swift \
//           -framework ApplicationServices -framework AppKit
//
// Requires Accessibility permission for whatever process runs axdrive
// (Terminal, or the compiled binary itself) — grant it once under
// System Settings → Privacy & Security → Accessibility.

import ApplicationServices
import AppKit
import Foundation

// MARK: - small helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func axAttr(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    return err == .success ? value : nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axAttr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func axIdentifier(_ element: AXUIElement) -> String? {
    axAttr(element, kAXIdentifierAttribute) as? String
}

func axValueDescription(_ element: AXUIElement) -> String {
    if let s = axAttr(element, kAXValueAttribute) as? String { return s }
    if let n = axAttr(element, kAXValueAttribute) as? NSNumber { return n.stringValue }
    if let s = axAttr(element, kAXTitleAttribute) as? String { return s }
    return ""
}

/// Depth-first search for the first descendant whose AXIdentifier == identifier.
func findElement(root: AXUIElement, identifier: String) -> AXUIElement? {
    var stack: [AXUIElement] = [root]
    var seen = 0
    while let el = stack.popLast() {
        seen += 1
        if seen > 20_000 { return nil } // guard against runaway trees
        if axIdentifier(el) == identifier { return el }
        stack.append(contentsOf: axChildren(el))
    }
    return nil
}

/// All AXWindows currently owned by the running app (includes MenuBarExtra
/// `.window`-style popovers and plain NSWindows such as the Settings window).
func windows(of appElement: AXUIElement) -> [AXUIElement] {
    (axAttr(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
}

func runningApp(bundleID: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

func appElement(bundleID: String) -> (AXUIElement, pid_t) {
    guard let app = runningApp(bundleID: bundleID) else {
        fail("axdrive: no running app with bundle id \(bundleID)")
    }
    return (AXUIElementCreateApplication(app.processIdentifier), app.processIdentifier)
}

/// Search across every window of the app for `identifier`.
func findInApp(bundleID: String, identifier: String) -> AXUIElement? {
    let (app, _) = appElement(bundleID: bundleID)
    for w in windows(of: app) {
        if let hit = findElement(root: w, identifier: identifier) { return hit }
    }
    // Some elements (e.g. the app element itself) may not be under a window.
    return findElement(root: app, identifier: identifier)
}

func requireTrusted() {
    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
        fail("""
        axdrive: this process is not trusted for Accessibility.
        Grant it under System Settings → Privacy & Security → Accessibility
        (the prompt should also have just appeared), then rerun.
        """)
    }
}

// MARK: - commands

func cmdLaunch(_ args: [String]) {
    guard let appPath = args.first else { fail("usage: axdrive launch <path-to-.app> [--arg ...] [--env KEY=VALUE ...]") }
    var launchArgs: [String] = []
    var env = ProcessInfo.processInfo.environment
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--arg":
            i += 1
            if i < args.count { launchArgs.append(args[i]) }
        case "--env":
            i += 1
            if i < args.count, let eq = args[i].firstIndex(of: "=") {
                env[String(args[i][..<eq])] = String(args[i][args[i].index(after: eq)...])
            }
        default: break
        }
        i += 1
    }

    let url = URL(fileURLWithPath: appPath)
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = launchArgs
    config.environment = env
    config.activates = true

    let sema = DispatchSemaphore(value: 0)
    var launchError: Error?
    var launchedPID: pid_t = 0
    NSWorkspace.shared.openApplication(at: url, configuration: config) { runningApp, error in
        launchError = error
        launchedPID = runningApp?.processIdentifier ?? 0
        sema.signal()
    }
    sema.wait()
    if let e = launchError { fail("axdrive: launch failed: \(e)") }
    print("launched pid \(launchedPID)")
}

func cmdTerminate(_ args: [String]) {
    guard let bundleID = args.first else { fail("usage: axdrive terminate <bundle-id>") }
    guard let app = runningApp(bundleID: bundleID) else { print("not running"); return }
    app.terminate()
    // Give it a moment; force if it refuses (e.g. mid-animation).
    for _ in 0..<20 {
        if app.isTerminated { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if !app.isTerminated { app.forceTerminate() }
    print("terminated")
}

func cmdFind(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: axdrive find <bundle-id> <identifier>") }
    guard let el = findInApp(bundleID: args[0], identifier: args[1]) else { fail("not found") }
    let role = axAttr(el, kAXRoleAttribute) as? String ?? "?"
    let enabled = (axAttr(el, kAXEnabledAttribute) as? Bool) ?? true
    print("role=\(role) enabled=\(enabled) value=\(axValueDescription(el))")
}

func cmdClick(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: axdrive click <bundle-id> <identifier>") }
    guard let el = findInApp(bundleID: args[0], identifier: args[1]) else { fail("not found: \(args[1])") }
    let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
    guard err == .success else { fail("press failed: \(err.rawValue)") }
    print("ok")
}

func cmdStep(_ args: [String], action: String) {
    guard args.count >= 2 else { fail("usage: axdrive \(action) <bundle-id> <identifier> [count]") }
    guard let el = findInApp(bundleID: args[0], identifier: args[1]) else { fail("not found: \(args[1])") }
    let count = args.count >= 3 ? (Int(args[2]) ?? 1) : 1
    let axAction = action == "increment" ? kAXIncrementAction : kAXDecrementAction
    for _ in 0..<max(1, count) {
        let err = AXUIElementPerformAction(el, axAction as CFString)
        guard err == .success else { fail("\(action) failed: \(err.rawValue)") }
    }
    print("ok")
}

func cmdRead(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: axdrive read <bundle-id> <identifier>") }
    guard let el = findInApp(bundleID: args[0], identifier: args[1]) else { fail("not found: \(args[1])") }
    print(axValueDescription(el))
}

/// Clicks the app's status-bar (menu-bar-extra) item to open/close its
/// popover. Status items aren't part of kAXWindows; they live under the
/// app's own `AXExtrasMenuBar` attribute (NOT the system-wide element).
func cmdMenuClick(_ args: [String]) {
    guard let bundleID = args.first else { fail("usage: axdrive menu-click <bundle-id>") }
    let (app, _) = appElement(bundleID: bundleID)
    guard let extrasBar = axAttr(app, "AXExtrasMenuBar") else {
        fail("axdrive: app has no AXExtrasMenuBar (is it running as a menu-bar-only app?)")
    }
    let extrasBarElement = extrasBar as! AXUIElement
    let items = axChildren(extrasBarElement)
    guard let item = items.first else {
        fail("axdrive: AXExtrasMenuBar has no status items")
    }
    let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
    guard err == .success else { fail("menu-click failed: \(err.rawValue)") }
    print("ok")
}

func cmdTree(_ args: [String]) {
    guard let bundleID = args.first else { fail("usage: axdrive tree <bundle-id>") }
    let (app, _) = appElement(bundleID: bundleID)
    func dump(_ el: AXUIElement, depth: Int) {
        let role = axAttr(el, kAXRoleAttribute) as? String ?? "?"
        let ident = axIdentifier(el).map { " id=\($0)" } ?? ""
        let title = (axAttr(el, kAXTitleAttribute) as? String).map { " title=\"\($0)\"" } ?? ""
        print(String(repeating: "  ", count: depth) + role + ident + title)
        for child in axChildren(el) { dump(child, depth: depth + 1) }
    }
    for w in windows(of: app) { dump(w, depth: 0) }
}

// MARK: - entry point

requireTrusted()

let argv = Array(CommandLine.arguments.dropFirst())
guard let command = argv.first else {
    fail("""
    usage: axdrive <command> [args...]
      launch <path-to-.app> [--arg X] [--env K=V]
      terminate <bundle-id>
      menu-click <bundle-id>
      find <bundle-id> <identifier>
      click <bundle-id> <identifier>
      increment <bundle-id> <identifier> [count]
      decrement <bundle-id> <identifier> [count]
      read <bundle-id> <identifier>
      tree <bundle-id>
    """)
}
let rest = Array(argv.dropFirst())
switch command {
case "launch": cmdLaunch(rest)
case "terminate": cmdTerminate(rest)
case "menu-click": cmdMenuClick(rest)
case "find": cmdFind(rest)
case "click": cmdClick(rest)
case "increment": cmdStep(rest, action: "increment")
case "decrement": cmdStep(rest, action: "decrement")
case "read": cmdRead(rest)
case "tree": cmdTree(rest)
default: fail("axdrive: unknown command '\(command)'")
}
