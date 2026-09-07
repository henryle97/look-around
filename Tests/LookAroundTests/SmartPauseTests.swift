import Foundation

func registerSmartPauseTests(_ r: TestRunner) {
    r.run("SmartPause: meeting app in front pauses") {
        let e = SmartPauseEvaluator(settings: SmartPauseSettings())
        let reason = e.pauseReason(frontmost: "zoom.us", running: [], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "In a meeting or call")
    }

    r.run("SmartPause: meeting check disabled lets the meeting app through") {
        var settings = SmartPauseSettings()
        settings.pauseOnMeetings = false
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "zoom.us", running: [], isFullscreen: false, frontmostBundle: "")
        try expectNil(reason)
    }

    r.run("SmartPause: recording app in front pauses") {
        let e = SmartPauseEvaluator(settings: SmartPauseSettings())
        let reason = e.pauseReason(frontmost: "obs", running: [], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "Recording or sharing screen")
    }

    r.run("SmartPause: foreground video pauses (background not included)") {
        var settings = SmartPauseSettings()
        settings.videoIncludesBackground = false
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "vlc", running: [], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "Watching video")
    }

    r.run("SmartPause: video-includes-background changes the reason text") {
        var settings = SmartPauseSettings()
        settings.videoIncludesBackground = true
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "vlc", running: [], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "Video playing")
    }

    r.run("SmartPause: screen-sharing check wins over video for an ambiguous app name") {
        // "quicktime" is both a recording hint and a video hint; screen-sharing
        // is checked first, so it takes priority — documents actual behavior.
        let e = SmartPauseEvaluator(settings: SmartPauseSettings())
        let reason = e.pauseReason(frontmost: "quicktime player", running: [], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "Recording or sharing screen")
    }

    r.run("SmartPause: deep focus 'When Open' matches a background running app") {
        var settings = SmartPauseSettings()
        settings.deepFocusMode = .open
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "finder", running: ["xcode"], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "Deep focus app open")
    }

    r.run("SmartPause: deep focus 'When in Foreground' ignores a background-only match") {
        var settings = SmartPauseSettings()
        settings.deepFocusMode = .foreground
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "finder", running: ["xcode"], isFullscreen: false, frontmostBundle: "")
        try expectNil(reason)
    }

    r.run("SmartPause: deep focus 'When in Foreground' matches the frontmost app") {
        var settings = SmartPauseSettings()
        settings.deepFocusMode = .foreground
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "xcode", running: [], isFullscreen: false, frontmostBundle: "")
        try expectEqual(reason, "In a deep focus app")
    }

    r.run("SmartPause: deep focus 'Foreground & Fullscreen' needs both") {
        var settings = SmartPauseSettings()
        settings.deepFocusMode = .foregroundFullscreen
        let e = SmartPauseEvaluator(settings: settings)
        try expectNil(e.pauseReason(frontmost: "xcode", running: [], isFullscreen: false, frontmostBundle: ""),
                       "foreground but windowed should not match")
        try expectEqual(e.pauseReason(frontmost: "xcode", running: [], isFullscreen: true, frontmostBundle: ""),
                         "In fullscreen focus")
    }

    r.run("SmartPause: unmatched fullscreen app pauses for gaming") {
        let e = SmartPauseEvaluator(settings: SmartPauseSettings()) // pauseOnGaming defaults true
        let reason = e.pauseReason(frontmost: "steam", running: ["steam"], isFullscreen: true, frontmostBundle: "")
        try expectEqual(reason, "Fullscreen app active")
    }

    r.run("SmartPause: focus mode pauses on fullscreen when gaming is off") {
        var settings = SmartPauseSettings()
        settings.pauseOnGaming = false
        settings.pauseOnFocusMode = true
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "steam", running: [], isFullscreen: true, frontmostBundle: "")
        try expectEqual(reason, "Focus mode: fullscreen app")
    }

    r.run("SmartPause: gaming check takes priority over focus mode") {
        var settings = SmartPauseSettings()
        settings.pauseOnGaming = true
        settings.pauseOnFocusMode = true
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "steam", running: [], isFullscreen: true, frontmostBundle: "")
        try expectEqual(reason, "Fullscreen app active")
    }

    r.run("SmartPause: nothing matches -> nil") {
        var settings = SmartPauseSettings()
        settings.deepFocusApps = []
        let e = SmartPauseEvaluator(settings: settings)
        let reason = e.pauseReason(frontmost: "textedit", running: ["textedit"], isFullscreen: false, frontmostBundle: "")
        try expectNil(reason)
    }
}
