import AppKit
import Foundation

/// Lightweight system activity probes using only public, permission-free APIs.
enum ActivityProbe {
    /// Call-first apps only. Chat-first apps (Slack, Discord) are excluded on
    /// purpose: being frontmost while chatting is not a call. If you take
    /// calls in them, add them as deep-focus apps with “When Open”.
    static let meetingBundleHints = [
        "zoom.us", "teams", "webex", "meet", "facetime",
        "skype", "gotomeeting", "whereby"
    ]
    static let videoAppHints = [
        "vlc", "iina", "quicktime", "netflix", "youtube",
        "movist", "mpv", "plex", "infuse"
    ]
    static let recordingHints = [
        "obs", "screenflow", "camtasia", "loom", "quicktime",
        "kap", "cleanShot"
    ]

    /// Seconds since last keyboard/mouse activity. Takes the minimum across
    /// HID event types — querying `.null` would return time since boot.
    static func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .keyDown, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .tabletPointer, .tabletProximity
        ]
        var best = TimeInterval.greatestFiniteMagnitude
        for t in types {
            let v = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: t)
            if v < best { best = v }
        }
        // CGEventSource returns ~1e9 on failure; treat as "active".
        if best > 1_000_000 { return 0 }
        return best
    }

    static func runningAppNames() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap {
            ($0.localizedName ?? $0.bundleIdentifier ?? "").lowercased()
        }
    }

    static func frontmostAppName() -> String {
        (NSWorkspace.shared.frontmostApplication?.localizedName
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            ?? "").lowercased()
    }

    static func frontmostBundleID() -> String {
        (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "").lowercased()
    }

    /// True when the frontmost window covers (nearly) a whole screen.
    /// Uses CGWindowList (no permissions needed).
    static func isFrontmostFullscreen() -> Bool {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for win in list {
            guard let pid = win[kCGWindowOwnerPID as String] as? Int32, pid == frontPID,
                  let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"]
            else { continue }
            let frame = NSRect(x: x, y: y, width: w, height: h)
            for screen in NSScreen.screens {
                // CG coords are flipped; compare sizes with tolerance instead of origins.
                if abs(frame.width - screen.frame.width) < 4 && abs(frame.height - screen.frame.height) < 4 {
                    return true
                }
            }
        }
        return false
    }

    static func containsHint(_ name: String, hints: [String]) -> Bool {
        hints.contains { name.contains($0) }
    }
}
