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
import CoreGraphics
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
    // A Text view that also carries an .accessibilityAction (used for
    // click-to-edit chips, see SettingsView.ChipStepper) gets promoted to
    // AXButton by the SwiftUI/AX bridge, which moves its label out of
    // AXValue/AXTitle into AXAttributedDescription (an NSAttributedString)
    // instead — plain AXDescription is never populated in that case.
    if let attributed = axAttr(element, "AXAttributedDescription") as? NSAttributedString {
        return attributed.string
    }
    if let s = axAttr(element, kAXDescriptionAttribute) as? String { return s }
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

func cmdAttrs(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: axdrive attrs <bundle-id> <identifier>") }
    guard let el = findInApp(bundleID: args[0], identifier: args[1]) else { fail("not found") }
    var names: CFArray?
    AXUIElementCopyAttributeNames(el, &names)
    for name in (names as? [String]) ?? [] {
        let v = axAttr(el, name)
        print("\(name) = \(String(describing: v))")
    }
}

func cmdClick(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: axdrive click <bundle-id> <identifier>") }
    // Retry the lookup briefly: the tree can be mid-mutation (a window
    // opening/closing on a timer) at the exact moment of a single lookup.
    var el: AXUIElement?
    for _ in 0..<10 {
        if let hit = findInApp(bundleID: args[0], identifier: args[1]) { el = hit; break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    guard let target = el else { fail("not found: \(args[1])") }
    let err = AXUIElementPerformAction(target, kAXPressAction as CFString)
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

/// Virtual keycodes for digits 0-9 and Return (US layout, position-based —
/// fine here since we only ever type digits).
private let digitKeyCodes: [Character: CGKeyCode] = [
    "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
    "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
]
private let returnKeyCode: CGKeyCode = 0x24
private let deleteKeyCode: CGKeyCode = 0x33
private let escapeKeyCode: CGKeyCode = 0x35

private func postKey(_ code: CGKeyCode, source: CGEventSource?) {
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.03)
}

/// Types digits into whatever text field currently has keyboard focus, via
/// synthetic keystrokes (not AXValue — SwiftUI's TextField binding doesn't
/// reliably observe a direct AXUIElementSetAttributeValue). Click the field
/// first (see `click`) so it's focused before calling this.
///   type <bundle-id> <digits> [--enter] [--escape] [--clear=N]
/// `--clear=N` backspaces N characters first (to replace existing content).
/// `--escape` sends Escape instead of typing (pass "" for <digits>).
func cmdType(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: axdrive type <bundle-id> <digits> [--enter] [--escape] [--clear=N]") }
    let bundleID = args[0]
    let digits = args[1]
    guard let app = runningApp(bundleID: bundleID) else { fail("axdrive: no running app with bundle id \(bundleID)") }
    for ch in digits {
        guard ch.isNumber else { fail("axdrive: type only supports digits, got '\(ch)'") }
    }
    // Synthetic key events go to whatever has OS-level key focus, unlike
    // AXUIElementPerformAction (used by `click`) which acts on the element
    // directly — so the target app must actually be frontmost first.
    app.activate(options: [])
    Thread.sleep(forTimeInterval: 0.15)
    let src = CGEventSource(stateID: .hidSystemState)
    for arg in args.dropFirst(2) {
        if arg.hasPrefix("--clear="), let n = Int(arg.dropFirst("--clear=".count)) {
            for _ in 0..<n { postKey(deleteKeyCode, source: src) }
        }
    }
    for ch in digits {
        guard let code = digitKeyCodes[ch] else { continue }
        postKey(code, source: src)
    }
    if args.contains("--enter") { postKey(returnKeyCode, source: src) }
    if args.contains("--escape") { postKey(escapeKeyCode, source: src) }
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

/// On-screen windows owned by `pid` (excludes desktop elements).
func cgWindows(ownerPID: pid_t) -> [[String: Any]] {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    return list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(ownerPID) }
}

func runScreencapture(_ args: [String], out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = args + [out]
    do {
        try p.run()
        p.waitUntilExit()
    } catch {
        fail("axdrive: screencapture failed: \(error)")
    }
    guard p.terminationStatus == 0 else { fail("axdrive: screencapture exited \(p.terminationStatus)") }
    print("ok")
}

/// Capture one app window by title substring:
///   shot-window <bundle-id> <title-substring> <out.png>
func cmdShotWindow(_ args: [String]) {
    guard args.count >= 3 else { fail("usage: axdrive shot-window <bundle-id> <title-substring> <out.png>") }
    guard let app = runningApp(bundleID: args[0]) else { fail("axdrive: no running app with bundle id \(args[0])") }
    let sub = args[1]
    let wins = cgWindows(ownerPID: app.processIdentifier)
    guard let num = wins.first(where: {
        (($0[kCGWindowName as String] as? String) ?? "").localizedCaseInsensitiveContains(sub)
    })?[kCGWindowNumber as String] as? Int else {
        fail("axdrive: no on-screen window of \(args[0]) with title containing '\(sub)'")
    }
    runScreencapture(["-l\(num)"], out: args[2])
}

/// Capture a whole display by 1-based index (1 = main display, others
/// left-to-right):   shot-display <index> <out.png>
func cmdShotDisplay(_ args: [String]) {
    guard args.count >= 2, let index = Int(args[0]), index >= 1 else {
        fail("usage: axdrive shot-display <1-based-index> <out.png>")
    }
    // NSScreen ordering follows the display arrangement; pin the main
    // display at index 1 for a stable mapping. screencapture -R wants
    // Quartz coords (y down from the main display's top), Cocoa frames are
    // y-up — convert.
    guard let main = NSScreen.main else { fail("axdrive: no displays found") }
    var rest = NSScreen.screens.filter { $0 != main }.sorted { $0.frame.minX < $1.frame.minX }
    let screens = [main] + rest
    guard index <= screens.count else {
        fail("axdrive: only \(screens.count) display(s) found")
    }
    let f = screens[index - 1].frame
    let qy = main.frame.height - (f.minY + f.height)
    let rect = "\(Int(f.minX)),\(Int(qy)),\(Int(f.width)),\(Int(f.height))"
    runScreencapture(["-R\(rect)"], out: args[1])
}

func cmdTree(_ args: [String]) {    guard let bundleID = args.first else { fail("usage: axdrive tree <bundle-id>") }
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
      attrs <bundle-id> <identifier>
      click <bundle-id> <identifier>
      increment <bundle-id> <identifier> [count]
      decrement <bundle-id> <identifier> [count]
      type <bundle-id> <digits> [--enter] [--escape] [--clear=N]
      read <bundle-id> <identifier>
      tree <bundle-id>
      shot-window <bundle-id> <title-substring> <out.png>
      shot-display <1-based-index> <out.png>
    """)
}
let rest = Array(argv.dropFirst())
switch command {
case "launch": cmdLaunch(rest)
case "terminate": cmdTerminate(rest)
case "menu-click": cmdMenuClick(rest)
case "find": cmdFind(rest)
case "attrs": cmdAttrs(rest)
case "click": cmdClick(rest)
case "increment": cmdStep(rest, action: "increment")
case "decrement": cmdStep(rest, action: "decrement")
case "type": cmdType(rest)
case "read": cmdRead(rest)
case "tree": cmdTree(rest)
case "shot-window": cmdShotWindow(rest)
case "shot-display": cmdShotDisplay(rest)
default: fail("axdrive: unknown command '\(command)'")
}
