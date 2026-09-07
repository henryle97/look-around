import Foundation
import AppKit

/// Runs user automations (shell / applescript / shortcuts) off the main thread.
enum AutomationRunner {
    static func run(_ script: AutomationScript) {
        DispatchQueue.global(qos: .utility).async {
            switch script.kind {
            case .shell:
                runShell(script.source)
            case .appleScript:
                runAppleScript(script.source)
            case .shortcut:
                runShortcut(named: script.source)
            }
        }
    }

    static func runAll(_ scripts: [AutomationScript], trigger: AutomationScript.Trigger) {
        for s in scripts where s.trigger == trigger { run(s) }
    }

    private static func runShell(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", source]
        try? p.run()
        p.waitUntilExit()
    }

    private static func runAppleScript(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        try? p.run()
        p.waitUntilExit()
    }

    private static func runShortcut(named: String) {
        let name = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
        p.waitUntilExit()
    }

    static func lockScreen() {
        runShell("/System/Library/CoreServices/Menu\\ Extras/User.menu/Contents/Resources/CGSession -suspend")
    }
}
