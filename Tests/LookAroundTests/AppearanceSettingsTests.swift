import Foundation

func registerAppearanceSettingsTests(_ r: TestRunner) {
    r.run("AppearanceSettings: decoding an old snapshot without appTheme/breakMaterial falls back to defaults") {
        // Simulates a settings snapshot written before appTheme/breakMaterial
        // existed (see the custom init(from:) in Models.swift) — must not
        // fail the whole decode over two missing keys.
        let json = """
        {
            "shortMessages": ["Look away"],
            "longMessages": ["Stretch"],
            "shortMessagesEnabled": false,
            "longMessagesEnabled": true,
            "gradientIndex": 2,
            "soundName": "rain",
            "soundVolume": 0.3,
            "customImagePath": ""
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: json)
        try expectEqual(decoded.appTheme, .system)
        try expectEqual(decoded.breakMaterial, .frosted)
        // Pre-BreakPrompt snapshots stored plain [String] pools — each string
        // becomes a .custom prompt (see AppearanceSettings.decodeMessagePool).
        try expectEqual(decoded.shortMessages.map(\.text), ["Look away"])
        try expectEqual(decoded.shortMessages.map(\.category), [.custom])
        try expectEqual(decoded.longMessages.map(\.text), ["Stretch"])
        try expectEqual(decoded.gradientIndex, 2)
        try expectEqual(decoded.soundName, .rain)
        try expectFalse(decoded.shortMessagesEnabled)
        // Personalize fields (backgroundMode, blur, per-event sound toggles,
        // custom sound paths) postdate this snapshot too — same fallback story.
        try expectEqual(decoded.backgroundMode, .wallpaper)
        try expectTrue(decoded.backgroundBlurEnabled)
        try expectTrue(decoded.soundOnStart)
        try expectTrue(decoded.soundOnEnd)
        try expectEqual(decoded.customStartSoundPath, "")
        try expectEqual(decoded.customEndSoundPath, "")
    }

    r.run("AppearanceSettings: the translucent app theme persists through a round-trip") {
        var original = AppearanceSettings()
        original.appTheme = .translucent

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: data)
        try expectEqual(decoded.appTheme, .translucent)
        // Raw value is what a settings snapshot on disk carries — pin it so a
        // rename can't silently reset users to .system on the next launch.
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try expectEqual(raw?["appTheme"] as? String, "translucent")
    }

    r.run("AppearanceSettings: encode/decode round-trips every field") {
        var original = AppearanceSettings()
        original.gradientIndex = 3
        original.soundVolume = 0.42
        original.appTheme = .dark
        original.breakMaterial = .liquidGlass
        original.shortMessagesEnabled = false
        original.backgroundMode = .customImage
        original.backgroundBlurEnabled = false
        original.soundOnStart = false
        original.soundOnEnd = true
        original.customStartSoundPath = "/Users/test/start.mp3"
        original.customEndSoundPath = "/Users/test/end.wav"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: data)

        try expectEqual(decoded.gradientIndex, original.gradientIndex)
        try expectEqual(decoded.soundVolume, original.soundVolume)
        try expectEqual(decoded.appTheme, original.appTheme)
        try expectEqual(decoded.breakMaterial, original.breakMaterial)
        try expectEqual(decoded.shortMessagesEnabled, original.shortMessagesEnabled)
        try expectEqual(decoded.shortMessages, original.shortMessages)
        try expectEqual(decoded.longMessages, original.longMessages)
        try expectEqual(decoded.backgroundMode, original.backgroundMode)
        try expectEqual(decoded.backgroundBlurEnabled, original.backgroundBlurEnabled)
        try expectEqual(decoded.soundOnStart, original.soundOnStart)
        try expectEqual(decoded.soundOnEnd, original.soundOnEnd)
        try expectEqual(decoded.customStartSoundPath, original.customStartSoundPath)
        try expectEqual(decoded.customEndSoundPath, original.customEndSoundPath)
    }
}
