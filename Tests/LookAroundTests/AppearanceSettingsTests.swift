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
    }

    r.run("AppearanceSettings: encode/decode round-trips every field") {
        var original = AppearanceSettings()
        original.gradientIndex = 3
        original.soundVolume = 0.42
        original.appTheme = .dark
        original.breakMaterial = .liquidGlass
        original.shortMessagesEnabled = false

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: data)

        try expectEqual(decoded.gradientIndex, original.gradientIndex)
        try expectEqual(decoded.soundVolume, original.soundVolume)
        try expectEqual(decoded.appTheme, original.appTheme)
        try expectEqual(decoded.breakMaterial, original.breakMaterial)
        try expectEqual(decoded.shortMessagesEnabled, original.shortMessagesEnabled)
        try expectEqual(decoded.shortMessages, original.shortMessages)
        try expectEqual(decoded.longMessages, original.longMessages)
    }
}
