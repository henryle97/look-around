import Foundation

/// Evaluates Smart Pause rules. Returns a human-readable reason when breaks must wait.
struct SmartPauseEvaluator {
    let settings: SmartPauseSettings

    /// - Parameters:
    ///   - frontmost: lowercase frontmost app name
    ///   - running: lowercase running app names
    ///   - isFullscreen: frontmost window covers a screen
    ///   - frontmostBundle: lowercase bundle id
    func pauseReason(
        frontmost: String, running: [String],
        isFullscreen: Bool, frontmostBundle: String
    ) -> String? {
        if settings.pauseOnMeetings {
            // Frontmost match only: background idling (e.g. an open but unused
            // QuickTime/Slack window) must not block breaks. For background
            // calls, add the app as a deep-focus app with "When Open".
            let meetingFront = ActivityProbe.containsHint(frontmost, hints: ActivityProbe.meetingBundleHints)
                || ActivityProbe.containsHint(frontmostBundle, hints: ActivityProbe.meetingBundleHints)
            if meetingFront {
                return "In a meeting or call"
            }
        }
        if settings.pauseOnScreenSharing {
            let recFront = ActivityProbe.containsHint(frontmost, hints: ActivityProbe.recordingHints)
                || ActivityProbe.containsHint(frontmostBundle, hints: ActivityProbe.recordingHints)
            if recFront {
                return "Recording or sharing screen"
            }
        }
        if settings.pauseOnVideo {
            let videoFront = ActivityProbe.containsHint(frontmost, hints: ActivityProbe.videoAppHints)
                || ActivityProbe.containsHint(frontmostBundle, hints: ActivityProbe.videoAppHints)
            if videoFront {
                if settings.videoIncludesBackground { return "Video playing" }
                // foreground-only: require frontmost match (already true) — still pause
                return "Watching video"
            }
        }
        // Deep focus apps
        let focusApps = settings.deepFocusApps.map { $0.lowercased() }
        if settings.pauseOnDeepFocus && !focusApps.isEmpty {
            let matchOpen = running.contains { r in focusApps.contains { r.contains($0) } }
            let matchFront = focusApps.contains { frontmost.contains($0) || frontmostBundle.contains($0) }
            switch settings.deepFocusMode {
            case .open:
                if matchOpen { return "Deep focus app open" }
            case .foreground:
                if matchFront { return "In a deep focus app" }
            case .foregroundFullscreen:
                if matchFront && isFullscreen { return "In fullscreen focus" }
            }
        }
        if settings.pauseOnGaming && isFullscreen {
            // Generic fullscreen fallback is handled by callers only when nothing else matched
            // and the frontmost app looks like a game (or always, per original default-on).
            return "Fullscreen app active"
        }
        if settings.pauseOnFocusMode && isFullscreen {
            // Heuristic: macOS exposes no Focus-state API, so Focus Mode pauses
            // while any app fills the screen.
            return "Focus mode: fullscreen app"
        }
        return nil
    }
}
