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

// MARK: - Break settings (short / long)
struct BreakSettings: Codable, Equatable {
    var workDuration: TimeInterval = 20 * 60      // 20 min
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

// MARK: - Appearance / customization
struct AppearanceSettings: Codable, Equatable {
    enum AppTheme: String, Codable, CaseIterable, Identifiable {
        case system, dark, light
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

    var shortMessages: [String] = [
        "Eyes to the horizon",
        "Breathe, relax, and come back",
        "Drink some water, look away, and come back",
        "Take a quick walk around the house"
    ]
    var longMessages: [String] = [
        "That was a good sprint - now relax",
        "Amazing work. Now it's time stretch those muscles",
        "You truly deserve this break!"
    ]
    var shortMessagesEnabled: Bool = true
    var longMessagesEnabled: Bool = true
    var gradientIndex: Int = 0
    var soundName: SoundName = .chime
    var soundVolume: Double = 0.7
    var customImagePath: String = ""
    var appTheme: AppTheme = .system
    var breakMaterial: BreakMaterial = .frosted

    enum SoundName: String, Codable, CaseIterable, Identifiable {
        case none, chime, rain, forest, waves
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    // Tolerate snapshots written before appTheme/breakMaterial existed:
    // missing keys fall back to defaults instead of failing the whole load.
    enum CodingKeys: String, CodingKey {
        case shortMessages, longMessages
        case shortMessagesEnabled, longMessagesEnabled
        case gradientIndex, soundName, soundVolume, customImagePath
        case appTheme, breakMaterial
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortMessages = try c.decodeIfPresent([String].self, forKey: .shortMessages) ?? [
            "Eyes to the horizon",
            "Breathe, relax, and come back",
            "Drink some water, look away, and come back",
            "Take a quick walk around the house"
        ]
        longMessages = try c.decodeIfPresent([String].self, forKey: .longMessages) ?? [
            "That was a good sprint - now relax",
            "Amazing work. Now it's time stretch those muscles",
            "You truly deserve this break!"
        ]
        shortMessagesEnabled = try c.decodeIfPresent(Bool.self, forKey: .shortMessagesEnabled) ?? true
        longMessagesEnabled = try c.decodeIfPresent(Bool.self, forKey: .longMessagesEnabled) ?? true
        gradientIndex = try c.decodeIfPresent(Int.self, forKey: .gradientIndex) ?? 0
        soundName = try c.decodeIfPresent(SoundName.self, forKey: .soundName) ?? .chime
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.7
        customImagePath = try c.decodeIfPresent(String.self, forKey: .customImagePath) ?? ""
        appTheme = try c.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .system
        breakMaterial = try c.decodeIfPresent(BreakMaterial.self, forKey: .breakMaterial) ?? .frosted
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
    }
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
