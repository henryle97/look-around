import Foundation

// MARK: - Skip difficulty
enum SkipDifficulty: String, Codable, CaseIterable, Identifiable {
    case casual, balanced, hardcore
    var id: String { rawValue }
    var label: String {
        switch self {
        case .casual: return "Casual — skip anytime"
        case .balanced: return "Balanced — skip after short delay"
        case .hardcore: return "Hardcore — cannot skip"
        }
    }
}

// MARK: - Break kind

enum BreakKind: String, Codable {
    case short, long, planned
    var label: String {
        switch self {
        case .short: return "Short break"
        case .long: return "Long break"
        case .planned: return "Planned break"
        }
    }
}

// MARK: - Break settings (short / long)
// Defaults follow the stretchly-style cadence (github.com/hovancik/stretchly):
// a 20-second mini break every 10 minutes, a 5-minute long break every 30
// minutes (every 3rd mini break, since 3 × 10 min = 30 min).
struct BreakSettings: Codable, Equatable {
    var workDuration: TimeInterval = 10 * 60      // 10 min
    var shortBreakDuration: TimeInterval = 20     // 20 sec
    var longBreakEnabled: Bool = true
    var longBreakDuration: TimeInterval = 5 * 60  // 5 min
    var longBreakEvery: Int = 3                    // every Nth break is long
    var skipDifficulty: SkipDifficulty = .balanced
    var skipDelay: TimeInterval = 5
    var snoozesPerDay: Int = 5
    var maxSnoozesPerBreak: Int = 0        // 0 = no per-break cap, only the daily budget applies
    var pausesPerDay: Int = 3
    var doubleEscapeAction: DoubleEscapeAction = .snooze5min
    var deferWhileTyping: Bool = true
    var allowEarlyEnd: Bool = true
    var earlyEndThreshold: TimeInterval = 5        // show "End break" in last N sec
    var lockMacOnBreak: Bool = false
    var preBreakWarningEnabled: Bool = true
    var preBreakLeadTime: TimeInterval = 60        // 1 min heads-up
    var preBreakVisibleFor: TimeInterval = 5
    var reminderPosition: ReminderPosition = .topCenter
    var countdownEnabled: Bool = true
    var countdownDuration: TimeInterval = 5        // floating "Starting break in NN"
    var overtimeNudgeEnabled: Bool = true
    var overtimeShowWhenPaused: Bool = true

    enum DoubleEscapeAction: String, Codable, CaseIterable, Identifiable {
        case snooze5min = "Snooze for 5 minutes"
        case skip = "Skip the break"
        case nothing = "Do nothing"
        var id: String { rawValue }
    }
    enum ReminderPosition: String, Codable, CaseIterable, Identifiable {
        case topLeft = "Top left"
        case topCenter = "Top center"
        case topRight = "Top right"
        var id: String { rawValue }
    }
}

// MARK: - Office hours
struct OfficeHours: Codable, Equatable {
    var enabled: Bool = false
    var days: Set<Int> = [1,2,3,4,5,6,7]
    var startMinutes: Int = 8 * 60
    var endMinutes: Int = 2 * 60

    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let wd = calendar.component(.weekday, from: date)
        guard days.contains(wd) else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let mins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if endMinutes <= startMinutes {
            // Overnight window, e.g. 08:00 → 02:00.
            return mins >= startMinutes || mins < endMinutes
        }
        return mins >= startMinutes && mins < endMinutes
    }
}

// MARK: - Planned break
struct PlannedBreak: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "Lunch"
    var hour: Int = 13
    var minute: Int = 0
    var duration: TimeInterval = 15 * 60
    var weekdays: Set<Int> = [2,3,4,5,6]
    var icon: String = "fork.knife"
    var enabled: Bool = true
    var syncToMobile: Bool = false

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - Smart pause
struct SmartPauseSettings: Codable, Equatable {
    var pauseOnMeetings: Bool = true
    var pauseOnVideo: Bool = true
    var videoIncludesBackground: Bool = false
    var pauseOnCalendarEvents: Bool = true
    var pauseOnGaming: Bool = true
    var pauseOnFocusMode: Bool = false
    var pauseOnDeepFocus: Bool = true
    var pauseOnScreenSharing: Bool = true
    var deepFocusApps: [String] = ["Keynote", "Xcode"] // bundle names / app names
    var deepFocusMode: DeepFocusMode = .foreground
    var cooldownAfterActivity: TimeInterval = 60
    var idleResetsCycle: Bool = true
    var ignoredMicrophoneApps: [String] = []

    enum DeepFocusMode: String, Codable, CaseIterable, Identifiable {
        case foregroundFullscreen = "When in Foreground & Fullscreen"
        case foreground = "When in Foreground"
        case open = "When Open"
        var id: String { rawValue }
    }
}

// MARK: - Wellness reminders
struct WellnessSettings: Codable, Equatable {
    var postureEnabled: Bool = true
    var postureInterval: TimeInterval = 30 * 60
    var blinkEnabled: Bool = true
    var blinkInterval: TimeInterval = 10 * 60
    var postureMessages: [String] = [
        "Sit tall — shoulders back",
        "Unclench your jaw, drop your shoulders",
        "Feet flat, screen at eye level"
    ]
    var blinkMessages: [String] = [
        "Blink and breathe",
        "20-20-20: look 20ft away for 20s",
        "Soften your gaze, blink slowly"
    ]
}

// MARK: - Update checking
struct UpdateSettings: Codable, Equatable {
    /// Whether `UpdateChecker` should run its once-at-launch + daily
    /// background check. The manual "Check for Updates" button (About page)
    /// works regardless of this setting.
    var autoCheckEnabled: Bool = true
    /// A release the user explicitly dismissed via "Skip this version" —
    /// suppresses the update banner/link until a newer one ships.
    var skippedVersion: String? = nil
    var lastCheckedAt: Date? = nil
}

// MARK: - Break-screen content (prompts)

/// What kind of instruction a break-screen prompt gives. Drives the emoji
/// prefix shown with the prompt and lets `PromptPicker` avoid showing the
/// same kind of thing twice in a row.
enum PromptCategory: String, Codable, CaseIterable, Identifiable, Equatable {
    case eyes, blink, posture, stretch, movement, breathing, water, mental, quote, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .eyes: return "Eyes"
        case .blink: return "Blink"
        case .posture: return "Posture"
        case .stretch: return "Stretch"
        case .movement: return "Movement"
        case .breathing: return "Breathing"
        case .water: return "Water"
        case .mental: return "Mental reset"
        case .quote: return "Quote"
        case .custom: return "Custom"
        }
    }
    var emoji: String {
        switch self {
        case .eyes: return "👀"
        case .blink: return "😌"
        case .posture: return "🧍"
        case .stretch: return "🤸"
        case .movement: return "🚶"
        case .breathing: return "🌬️"
        case .water: return "💧"
        case .mental: return "🧠"
        case .quote: return "🌿"
        case .custom: return ""
        }
    }
}

/// One break-screen message. `weight` biases random selection (higher =
/// shown more often); `PromptPicker` (Helpers.swift) is what actually picks
/// one, favoring unseen prompts and a different category than last time.
struct BreakPrompt: Codable, Equatable, Identifiable {
    var id: String
    var category: PromptCategory
    var text: String
    var weight: Int = 1

    var displayText: String { category.emoji.isEmpty ? text : "\(category.emoji) \(text)" }
}

/// Loads the curated break-prompt pools from `BreakPrompts.json` in the app
/// bundle (adapted from stretchly's BSD-2-Clause `miniBreakIdeas`/
/// `longBreakIdeas`, github.com/hovancik/stretchly — trimmed to one
/// instruction each). Content lives in JSON rather than Swift so it's easy
/// to extend without recompiling.
///
/// Falls back to a small embedded set if the resource can't be loaded —
/// e.g. the standalone `Tests/LookAroundTests` binary has no app bundle at
/// all, so it always exercises this fallback rather than the JSON file.
enum BreakPromptLibrary {
    private struct File: Codable {
        var short: [BreakPrompt]
        var long: [BreakPrompt]
    }

    static let shared: (short: [BreakPrompt], long: [BreakPrompt]) = load()

    private static func load() -> (short: [BreakPrompt], long: [BreakPrompt]) {
        guard let url = Bundle.main.url(forResource: "BreakPrompts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              !file.short.isEmpty, !file.long.isEmpty
        else {
            return (fallbackShort, fallbackLong)
        }
        return (file.short, file.long)
    }

    private static let fallbackShort: [BreakPrompt] = [
        BreakPrompt(id: "short-eyes-distance", category: .eyes, text: "Look at something about 6 m / 20 ft away.", weight: 3),
        BreakPrompt(id: "short-eyes-farthest", category: .eyes, text: "Find the farthest point you can see and hold your gaze there.", weight: 1),
        BreakPrompt(id: "short-eyes-window", category: .eyes, text: "Look out a window and focus on the horizon.", weight: 1),
        BreakPrompt(id: "short-blink-slow", category: .blink, text: "Blink slowly ten times.", weight: 1),
        BreakPrompt(id: "short-blink-close", category: .blink, text: "Close your eyes for a few seconds, then open slowly.", weight: 1),
        BreakPrompt(id: "short-posture-shoulders", category: .posture, text: "Roll your shoulders back and drop them.", weight: 1),
        BreakPrompt(id: "short-posture-sit", category: .posture, text: "Sit up, feet flat, screen at eye level.", weight: 1),
        BreakPrompt(id: "short-stretch-neck-turn", category: .stretch, text: "Slowly turn your head to one side and hold for 10 seconds.", weight: 1),
        BreakPrompt(id: "short-breathing-three", category: .breathing, text: "Take three slow breaths.", weight: 1),
        BreakPrompt(id: "short-breathing-count", category: .breathing, text: "Inhale for four counts, exhale for four.", weight: 1),
    ]

    private static let fallbackLong: [BreakPrompt] = [
        BreakPrompt(id: "long-movement-walk", category: .movement, text: "Stand up and walk around for a minute.", weight: 3),
        BreakPrompt(id: "long-movement-another-room", category: .movement, text: "Walk to another room and back.", weight: 1),
        BreakPrompt(id: "long-stretch-arms", category: .stretch, text: "Stretch your arms overhead and hold.", weight: 1),
        BreakPrompt(id: "long-stretch-shoulders", category: .stretch, text: "Roll your shoulders backward, five times.", weight: 1),
        BreakPrompt(id: "long-water-glass", category: .water, text: "Grab a glass of water.", weight: 1),
        BreakPrompt(id: "long-mental-step-away", category: .mental, text: "Step away from the problem — your brain can work without you.", weight: 1),
        BreakPrompt(id: "long-mental-gratitude", category: .mental, text: "Think of one thing that went well today.", weight: 1),
        BreakPrompt(id: "long-quote-still-here", category: .quote, text: "The screen will still be here.", weight: 1),
        BreakPrompt(id: "long-quote-part-of-work", category: .quote, text: "A short pause is part of the work.", weight: 1),
        BreakPrompt(id: "long-quote-leave", category: .quote, text: "Leave the screen for a moment.", weight: 1),
    ]
}

// MARK: - Appearance / customization
struct AppearanceSettings: Codable, Equatable {
    enum AppTheme: String, Codable, CaseIterable, Identifiable {
        /// `.translucent` is a dark theme that lets the desktop show through
        /// the app's own chrome (settings window + menu-bar popup) instead of
        /// painting opaque fills.
        case system, dark, light, translucent
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum BreakMaterial: String, Codable, CaseIterable, Identifiable {
        case frosted
        case liquidGlass
        var id: String { rawValue }
        var label: String {
            switch self {
            case .frosted: return "Frosted"
            case .liquidGlass: return "Liquid Glass"
            }
        }
    }

    /// What the break screen renders behind the card. `.gradient` ignores
    /// `backgroundBlurEnabled` (there's nothing to blur on a flat fill).
    enum BackgroundMode: String, Codable, CaseIterable, Identifiable {
        case wallpaper, customImage, gradient
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wallpaper: return "Wallpaper"
            case .customImage: return "Custom Image"
            case .gradient: return "Gradient"
            }
        }
    }

    var shortMessages: [BreakPrompt] = AppearanceSettings.defaultShortMessages
    var longMessages: [BreakPrompt] = AppearanceSettings.defaultLongMessages
    var shortMessagesEnabled: Bool = true
    var longMessagesEnabled: Bool = true
    var gradientIndex: Int = 0
    var soundName: SoundName = .chime
    var soundVolume: Double = 0.7
    var customImagePath: String = ""
    var appTheme: AppTheme = .system
    var breakMaterial: BreakMaterial = .frosted
    var backgroundMode: BackgroundMode = .wallpaper
    var backgroundBlurEnabled: Bool = true
    var soundOnStart: Bool = true
    var soundOnEnd: Bool = true
    var customStartSoundPath: String = ""
    var customEndSoundPath: String = ""

    enum SoundName: String, Codable, CaseIterable, Identifiable {
        case none, chime, rain, forest, waves
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    // Tolerate snapshots written before appTheme/breakMaterial (and later,
    // backgroundMode/soundOnStart/soundOnEnd/custom sound paths) existed:
    // missing keys fall back to defaults instead of failing the whole load.
    enum CodingKeys: String, CodingKey {
        case shortMessages, longMessages
        case shortMessagesEnabled, longMessagesEnabled
        case gradientIndex, soundName, soundVolume, customImagePath
        case appTheme, breakMaterial
        case backgroundMode, backgroundBlurEnabled
        case soundOnStart, soundOnEnd, customStartSoundPath, customEndSoundPath
    }

    init() {}

    /// Decodes a message pool, tolerating a pre-`BreakPrompt` snapshot where
    /// the key held a plain `[String]`: each string becomes a `.custom`
    /// prompt with a stable synthetic id so old settings still load.
    private static func decodeMessagePool(
        _ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys, default def: [BreakPrompt]
    ) -> [BreakPrompt] {
        if let prompts = try? c.decode([BreakPrompt].self, forKey: key) { return prompts }
        if let legacy = try? c.decode([String].self, forKey: key) {
            return legacy.enumerated().map { i, text in
                BreakPrompt(id: "legacy-\(key.rawValue)-\(i)", category: .custom, text: text, weight: 1)
            }
        }
        return def
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortMessages = Self.decodeMessagePool(c, forKey: .shortMessages, default: Self.defaultShortMessages)
        longMessages = Self.decodeMessagePool(c, forKey: .longMessages, default: Self.defaultLongMessages)
        shortMessagesEnabled = try c.decodeIfPresent(Bool.self, forKey: .shortMessagesEnabled) ?? true
        longMessagesEnabled = try c.decodeIfPresent(Bool.self, forKey: .longMessagesEnabled) ?? true
        gradientIndex = try c.decodeIfPresent(Int.self, forKey: .gradientIndex) ?? 0
        soundName = try c.decodeIfPresent(SoundName.self, forKey: .soundName) ?? .chime
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.7
        customImagePath = try c.decodeIfPresent(String.self, forKey: .customImagePath) ?? ""
        appTheme = try c.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .system
        breakMaterial = try c.decodeIfPresent(BreakMaterial.self, forKey: .breakMaterial) ?? .frosted
        backgroundMode = try c.decodeIfPresent(BackgroundMode.self, forKey: .backgroundMode) ?? .wallpaper
        backgroundBlurEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundBlurEnabled) ?? true
        soundOnStart = try c.decodeIfPresent(Bool.self, forKey: .soundOnStart) ?? true
        soundOnEnd = try c.decodeIfPresent(Bool.self, forKey: .soundOnEnd) ?? true
        customStartSoundPath = try c.decodeIfPresent(String.self, forKey: .customStartSoundPath) ?? ""
        customEndSoundPath = try c.decodeIfPresent(String.self, forKey: .customEndSoundPath) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shortMessages, forKey: .shortMessages)
        try c.encode(longMessages, forKey: .longMessages)
        try c.encode(shortMessagesEnabled, forKey: .shortMessagesEnabled)
        try c.encode(longMessagesEnabled, forKey: .longMessagesEnabled)
        try c.encode(gradientIndex, forKey: .gradientIndex)
        try c.encode(soundName, forKey: .soundName)
        try c.encode(soundVolume, forKey: .soundVolume)
        try c.encode(customImagePath, forKey: .customImagePath)
        try c.encode(appTheme, forKey: .appTheme)
        try c.encode(breakMaterial, forKey: .breakMaterial)
        try c.encode(backgroundMode, forKey: .backgroundMode)
        try c.encode(backgroundBlurEnabled, forKey: .backgroundBlurEnabled)
        try c.encode(soundOnStart, forKey: .soundOnStart)
        try c.encode(soundOnEnd, forKey: .soundOnEnd)
        try c.encode(customStartSoundPath, forKey: .customStartSoundPath)
        try c.encode(customEndSoundPath, forKey: .customEndSoundPath)
    }

    // MARK: default prompt pools
    //
    // Short pool: shown during 20-second eye breaks — one clear instruction,
    // nothing to read. Long pool: shown during 5-minute breaks — movement,
    // stretches, water, and a lighter mental-reset/quote mix. The full,
    // stretchly-inspired library ships as `BreakPrompts.json` in the app
    // bundle (see `BreakPromptLibrary`) so it's easy to extend without
    // recompiling; these just forward to whatever that loaded.
    static var defaultShortMessages: [BreakPrompt] { BreakPromptLibrary.shared.short }
    static var defaultLongMessages: [BreakPrompt] { BreakPromptLibrary.shared.long }
}

// MARK: - Automations
struct AutomationScript: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "New automation"
    var trigger: Trigger = .onBreakStart
    var kind: Kind = .shell
    var source: String = "osascript -e 'display notification \"Break started\"'"

    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case onBreakStart = "When break starts"
        case onBreakEnd = "When break ends"
        var id: String { rawValue }
    }
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case shell = "Shell script"
        case appleScript = "AppleScript"
        case shortcut = "Shortcut"
        var id: String { rawValue }
    }
}

// MARK: - Stats
struct BreakStats: Codable, Equatable {
    var shortBreaksTaken: Int = 0
    var longBreaksTaken: Int = 0
    var plannedBreaksTaken: Int = 0
    var breaksSkipped: Int = 0
    var breaksPostponed: Int = 0
    var snoozesUsedToday: Int = 0
    var snoozeDayKey: String = ""
    var snoozesUsedThisCycle: Int = 0
    var pausesUsedToday: Int = 0
    var pauseDayKey: String = ""
    var naturalBreaks: Int = 0
    var naturalBreakMinutes: Double = 0
    var screenTimeTodayMinutes: Double = 0
    var screenTimeDayKey: String = ""
    var totalScreenMinutes: Double = 0
    var streakDays: Int = 0
    var lastBreakDate: Date? = nil
}
