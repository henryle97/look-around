import Foundation
import Combine
import AppKit
import UserNotifications

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

struct BreakSession: Equatable {
    var kind: BreakKind
    var title: String
    var subtitle: String
    var total: TimeInterval
    var remaining: TimeInterval
    var message: String
    var startedAt: Date
}

/// Core timer engine. Ticks every second, drives menu bar + overlays.
/// NOTE: intentionally NOT @MainActor — the App struct's init() is nonisolated
/// and constructing a @MainActor type there traps at runtime (EXC_BREAKPOINT).
/// The Timer publishes on .main so all ticks/mutations already run on the main thread.
final class BreakScheduler: ObservableObject {
    // MARK: published UI state
    @Published var timeUntilNextBreak: TimeInterval? = nil
    @Published var smartPauseReason: String? = nil
    @Published var cooldownRemaining: TimeInterval = 0
    @Published var isOnBreak = false
    @Published var session: BreakSession? = nil
    @Published var canSkip = false
    @Published var canEndEarly = false
    @Published var preBreakVisible = false
    @Published var preBreakCountdown: TimeInterval = 0
    @Published var countdownVisible = false
    @Published var countdownSeconds: TimeInterval = 0
    @Published var isOvertime = false
    @Published var overtimeElapsed: TimeInterval = 0
    @Published var overtimeVisible = false
    @Published var snoozesLeft: Int = 5
    @Published var pausesLeft: Int = 3
    @Published var manuallyPaused = false
    @Published var pauseRemaining: TimeInterval = 0
    @Published var nextPlanned: PlannedBreak? = nil
    @Published var lastWellnessMessage: String? = nil

    let settings: SettingsStore
    lazy var calendarMonitor = CalendarMonitor()

    private var timer: AnyCancellable?
    private var nextBreakAt: Date
    private var shortBreaksCompleted = 0
    private var activityWasActive = false
    private var cooldownUntil: Date? = nil
    private var firedPlannedToday: Set<String> = [] // plannedID + dayKey
    private var deferredPlanned: PlannedBreak? = nil
    private var skipAllowedAt: Date = Date()
    private var postureNextAt: Date
    private var blinkNextAt: Date
    private var idleEpisodeCounted = false
    private var idleResetDone = false
    private var recentShortPromptIDs: [String] = []
    private var recentLongPromptIDs: [String] = []
    private var lastShortCategory: PromptCategory? = nil
    private var lastLongCategory: PromptCategory? = nil

    init(settings: SettingsStore) {
        self.settings = settings
        let now = Date()
        self.nextBreakAt = now.addingTimeInterval(settings.breaks.workDuration)
        self.postureNextAt = now.addingTimeInterval(settings.wellness.postureInterval)
        self.blinkNextAt = now.addingTimeInterval(settings.wellness.blinkInterval)
        requestNotificationPermission()
        start()
    }

    func start() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    // MARK: - public controls

    func startBreakNow(kind: BreakKind = .short) {
        preBreakVisible = false
        beginBreak(kind: kind, planned: nil)
    }

    func snoozePreBreak(by interval: TimeInterval) {
        guard snoozesLeft > 0 else { return }
        consumeSnooze()
        nextBreakAt = Date().addingTimeInterval(interval)
        preBreakVisible = false
        settings.stats.breaksPostponed += 1
    }

    /// Snooze from the break screen (double-Esc / Skip pill consumes one too).
    @discardableResult
    func snoozeBreakScreen(by interval: TimeInterval) -> Bool {
        guard snoozesLeft > 0 else { return false }
        consumeSnooze()
        isOnBreak = false
        session = nil
        canSkip = false
        canEndEarly = false
        nextBreakAt = Date().addingTimeInterval(interval)
        timeUntilNextBreak = interval
        settings.stats.breaksPostponed += 1
        return true
    }

    private func consumeSnooze() {
        rollDayIfNeeded()
        settings.stats.snoozesUsedToday += 1
        settings.stats.snoozesUsedThisCycle += 1
        recomputeSnoozesLeft()
    }

    /// Effective remaining snoozes: the tighter of the daily budget and the
    /// per-break-cycle cap (0 in `maxSnoozesPerBreak` means no per-cycle cap).
    private func recomputeSnoozesLeft() {
        let daily = max(0, settings.breaks.snoozesPerDay - settings.stats.snoozesUsedToday)
        guard settings.breaks.maxSnoozesPerBreak > 0 else { snoozesLeft = daily; return }
        let perCycle = max(0, settings.breaks.maxSnoozesPerBreak - settings.stats.snoozesUsedThisCycle)
        snoozesLeft = min(daily, perCycle)
    }

    private func rollDayIfNeeded() {
        let key = dayKey(Date())
        if settings.stats.snoozeDayKey != key {
            settings.stats.snoozeDayKey = key
            settings.stats.snoozesUsedToday = 0
        }
        if settings.stats.screenTimeDayKey != key {
            settings.stats.screenTimeDayKey = key
            settings.stats.screenTimeTodayMinutes = 0
        }
        if settings.stats.pauseDayKey != key {
            settings.stats.pauseDayKey = key
            settings.stats.pausesUsedToday = 0
        }
        recomputeSnoozesLeft()
        pausesLeft = max(0, settings.breaks.pausesPerDay - settings.stats.pausesUsedToday)
    }

    func handleDoubleEscape() {
        guard isOnBreak else { return }
        switch settings.breaks.doubleEscapeAction {
        case .snooze5min:
            _ = snoozeBreakScreen(by: 5 * 60)
        case .skip:
            if canSkip || settings.breaks.skipDifficulty == .casual { endBreak(skipped: true) }
        case .nothing:
            break
        }
    }

    func lockScreenNow() {
        AutomationRunner.lockScreen()
    }

    func advanceSkip() {
        // "Skip upcoming break": push by one work interval. This postpones
        // the break exactly like a snooze does, so it draws from the same
        // budget instead of bypassing it.
        guard snoozesLeft > 0 else { return }
        consumeSnooze()
        nextBreakAt = Date().addingTimeInterval(settings.breaks.workDuration)
        preBreakVisible = false
        settings.stats.breaksSkipped += 1
    }

    func skipCurrentBreak() {
        guard isOnBreak, canSkip else { return }
        endBreak(skipped: true)
    }

    func endBreakEarly() {
        guard isOnBreak, canEndEarly else { return }
        endBreak(skipped: false)
    }

    func pauseWork(for interval: TimeInterval) {
        guard pausesLeft > 0 else { return }
        rollDayIfNeeded()
        settings.stats.pausesUsedToday += 1
        pausesLeft = max(0, settings.breaks.pausesPerDay - settings.stats.pausesUsedToday)
        manuallyPaused = true
        pauseRemaining = interval
        settings.isPaused = true
        settings.pauseUntil = Date().addingTimeInterval(interval)
    }

    func resumeWork() {
        manuallyPaused = false
        pauseRemaining = 0
        settings.isPaused = false
        settings.pauseUntil = nil
        // push schedule forward by pause length? keep simple: restart work interval
        nextBreakAt = Date().addingTimeInterval(max(60, timeUntilNextBreak ?? settings.breaks.workDuration))
    }

    func resetCycle() {
        nextBreakAt = Date().addingTimeInterval(settings.breaks.workDuration)
        shortBreaksCompleted = 0
        isOvertime = false
        overtimeElapsed = 0
        preBreakVisible = false
    }

    // MARK: - menu-bar hero (read-only, for MenuBarView)

    /// Next regular-break kind, exposed so the popup hero can label it.
    var upcomingKind: BreakKind { nextBreakKind() }

    var upcomingDuration: TimeInterval {
        switch upcomingKind {
        case .short: return settings.breaks.shortBreakDuration
        case .long: return settings.breaks.longBreakDuration
        case .planned: return settings.breaks.shortBreakDuration
        }
    }

    /// Focus time elapsed in the current work stretch.
    var focusTimeElapsed: TimeInterval {
        guard let t = timeUntilNextBreak else { return 0 }
        return max(0, settings.breaks.workDuration - t)
    }

    // MARK: - tick

    private func tick() {
        let now = Date()
        rollDayIfNeeded()

        // Manual pause
        if manuallyPaused {
            if let until = settings.pauseUntil {
                pauseRemaining = max(0, until.timeIntervalSince(now))
                if pauseRemaining <= 0 { resumeWork(); return }
            } else if pauseRemaining > 0 {
                pauseRemaining -= 1
                if pauseRemaining <= 0 { resumeWork(); return }
            }
            timeUntilNextBreak = settings.pauseUntil?.timeIntervalSince(now)
            // Overtime pill can optionally linger while paused.
            if settings.breaks.overtimeNudgeEnabled && settings.breaks.overtimeShowWhenPaused {
                updateOvertime(now: now)
            } else {
                clearOvertime()
            }
            return
        }
        if let until = settings.pauseUntil, until > now {
            manuallyPaused = true
            pauseRemaining = until.timeIntervalSince(now)
            return
        }

        // On break: count down
        if isOnBreak, var s = session {
            s.remaining = max(0, s.remaining - 1)
            session = s
            let elapsed = s.total - s.remaining
            switch settings.breaks.skipDifficulty {
            case .casual: canSkip = true
            case .balanced: canSkip = elapsed >= settings.breaks.skipDelay
            case .hardcore: canSkip = false
            }
            canEndEarly = settings.breaks.allowEarlyEnd && s.remaining <= settings.breaks.earlyEndThreshold && s.remaining > 0
            if s.remaining <= 0 { endBreak(skipped: false) }
            return
        }

        // --- Working state ---
        updateNextPlannedLabel(now: now)

        // Planned breaks (run even outside office hours)
        checkPlannedBreaks(now: now)

        // Office hours gate (regular breaks only)
        if !settings.officeHours.isActive(at: now) {
            smartPauseReason = nil
            timeUntilNextBreak = nil
            preBreakVisible = false
            // still tick wellness? no — pause everything outside hours
            return
        }

        // Smart pause probe (throttle: every tick is fine, cheap)
        let frontmost = ActivityProbe.frontmostAppName()
        let bundle = ActivityProbe.frontmostBundleID()
        let running = ActivityProbe.runningAppNames()
        let fullscreen = ActivityProbe.isFrontmostFullscreen()
        let evaluator = SmartPauseEvaluator(settings: settings.smartPause)
        let probeReason = evaluator.pauseReason(frontmost: frontmost, running: running,
                                                isFullscreen: fullscreen, frontmostBundle: bundle)
        let calendarReason: String? = (settings.smartPause.pauseOnCalendarEvents
            && CalendarMonitor.isAuthorized
            && calendarMonitor.isInEvent(now: now)) ? "In a calendar event" : nil
        let reason = probeReason ?? calendarReason

        if let reason {
            smartPauseReason = reason
            activityWasActive = true
            // Freeze countdown while engaged; a deferred planned break keeps waiting.
            updateOvertime(now: now)
            return
        } else {
            smartPauseReason = nil
            if activityWasActive {
                activityWasActive = false
                cooldownUntil = now.addingTimeInterval(settings.smartPause.cooldownAfterActivity)
            }
        }
        if let cd = cooldownUntil, cd > now {
            cooldownRemaining = cd.timeIntervalSince(now)
            updateOvertime(now: now)
            return
        }
        cooldownRemaining = 0

        // Fire deferred planned break once clear
        if let deferred = deferredPlanned {
            deferredPlanned = nil
            beginBreak(kind: .planned, planned: deferred)
            return
        }

        // Away detection: if user idle > 60s, freeze work timer (they're already away).
        // Away stretches count as natural breaks.
        let idle = ActivityProbe.idleSeconds()
        if idle > 60 {
            timeUntilNextBreak = nextBreakAt.timeIntervalSince(now)
            settings.stats.naturalBreakMinutes += 1.0 / 60.0
            if idle > 5 * 60 && !idleEpisodeCounted {
                idleEpisodeCounted = true
                settings.stats.naturalBreaks += 1
            }
            if idle > 10 * 60 && !idleResetDone {
                idleResetDone = true
                if settings.smartPause.idleResetsCycle { resetCycle() }
            }
            return
        }
        idleEpisodeCounted = false
        idleResetDone = false

        var remaining = nextBreakAt.timeIntervalSince(now)

        // Typing/drag defer: if break imminent but user actively interacting, nudge forward
        if settings.breaks.deferWhileTyping && remaining <= 2 && remaining > -30 && idle < 2 {
            nextBreakAt = now.addingTimeInterval(6)
            remaining = 6
        }

        // Due → start the break now (smart pause already clear).
        if remaining <= 0 {
            beginBreak(kind: nextBreakKind())
            return
        }
        clearOvertime()
        timeUntilNextBreak = remaining

        // Screen-time accrual (only while present and inside office hours).
        settings.stats.screenTimeTodayMinutes += 1.0 / 60.0
        settings.stats.totalScreenMinutes += 1.0 / 60.0

        // Heads-up reminder: appears `lead` before the break, stays `visibleFor`.
        let lead = settings.breaks.preBreakLeadTime
        let visibleFor = max(1, settings.breaks.preBreakVisibleFor)
        if settings.breaks.preBreakWarningEnabled && remaining <= lead && remaining > lead - visibleFor {
            preBreakVisible = true
            preBreakCountdown = remaining
        } else {
            preBreakVisible = false
        }

        // Floating "Starting break in NN" pill during the final seconds.
        if settings.breaks.countdownEnabled
            && remaining <= max(1, settings.breaks.countdownDuration) && remaining > 0 {
            countdownVisible = true
            countdownSeconds = remaining
        } else {
            countdownVisible = false
        }

        // Wellness reminders
        tickWellness(now: now, idle: idle)
    }

    // MARK: - overtime

    /// Shows the overtime pill when the break is overdue but held back
    /// (smart pause, cooldown, …). Called on the deferral paths only.
    private func updateOvertime(now: Date) {
        let overdue = -nextBreakAt.timeIntervalSince(now)
        if settings.breaks.overtimeNudgeEnabled && overdue > 0 {
            isOvertime = true
            overtimeElapsed = overdue
            overtimeVisible = true
        } else {
            clearOvertime()
        }
    }

    private func clearOvertime() {
        isOvertime = false
        overtimeElapsed = 0
        overtimeVisible = false
    }

    // MARK: - breaks

    private func nextBreakKind() -> BreakKind {
        let b = settings.breaks
        guard b.longBreakEnabled else { return .short }
        let upcoming = shortBreaksCompleted + 1
        if upcoming % max(1, b.longBreakEvery) == 0 { return .long }
        return .short
    }

    /// Picks the next break-screen prompt for `kind`, tracking a short
    /// recent-history per pool (short/long breaks draw from separate pools,
    /// so their histories don't interfere) — see `PromptPicker`.
    private func pickPrompt(for kind: BreakKind, from pool: [BreakPrompt]) -> BreakPrompt? {
        let isLong = kind == .long
        let recent = isLong ? recentLongPromptIDs : recentShortPromptIDs
        let lastCategory = isLong ? lastLongCategory : lastShortCategory
        guard let prompt = PromptPicker.pick(from: pool, recentIDs: recent, lastCategory: lastCategory) else { return nil }
        if isLong {
            lastLongCategory = prompt.category
            recentLongPromptIDs.append(prompt.id)
            if recentLongPromptIDs.count > 6 { recentLongPromptIDs.removeFirst() }
        } else {
            lastShortCategory = prompt.category
            recentShortPromptIDs.append(prompt.id)
            if recentShortPromptIDs.count > 6 { recentShortPromptIDs.removeFirst() }
        }
        return prompt
    }

    private func beginBreak(kind: BreakKind, planned: PlannedBreak? = nil) {
        let b = settings.breaks
        rollDayIfNeeded()
        // Fresh per-break snooze budget for this break's own screen (snoozes
        // spent postponing it while it was still upcoming don't carry over).
        settings.stats.snoozesUsedThisCycle = 0
        recomputeSnoozesLeft()
        let duration: TimeInterval
        let subtitle: String
        switch kind {
        case .short:
            duration = b.shortBreakDuration
            subtitle = "Set your eyes on something distant until the countdown is over"
        case .long:
            duration = b.longBreakDuration
            subtitle = "Stretch, hydrate and rest until the countdown is over"
        case .planned:
            duration = planned?.duration ?? 5*60
            subtitle = "Step away and recharge until the countdown is over"
        }
        let pool: [BreakPrompt]
        let poolEnabled: Bool
        switch kind {
        case .long:
            pool = settings.appearance.longMessages
            poolEnabled = settings.appearance.longMessagesEnabled
        default:
            pool = settings.appearance.shortMessages
            poolEnabled = settings.appearance.shortMessagesEnabled
        }
        let title: String
        if kind == .planned, let p = planned {
            title = p.name
        } else if poolEnabled, let prompt = pickPrompt(for: kind, from: pool) {
            title = prompt.displayText
        } else {
            title = kind == .long ? "Time for a long break" : "Time for a quick break"
        }
        session = BreakSession(kind: kind, title: title, subtitle: subtitle, total: duration,
                               remaining: duration, message: title, startedAt: Date())
        isOnBreak = true
        preBreakVisible = false
        countdownVisible = false
        clearOvertime()
        skipAllowedAt = Date().addingTimeInterval(b.skipDelay)
        canSkip = b.skipDifficulty == .casual
        canEndEarly = false
        SoundPlayer.playBreakStart(settings.appearance)
        AutomationRunner.runAll(settings.automations, trigger: .onBreakStart)
        if b.lockMacOnBreak && kind != .short {
            AutomationRunner.lockScreen()
        }
        settings.stats.lastBreakDate = Date()
    }

    private func endBreak(skipped: Bool) {
        guard let s = session else { isOnBreak = false; return }
        if skipped {
            settings.stats.breaksSkipped += 1
        } else {
            switch s.kind {
            case .short:
                settings.stats.shortBreaksTaken += 1
                shortBreaksCompleted += 1
            case .long:
                settings.stats.longBreaksTaken += 1
                shortBreaksCompleted = 0
            case .planned:
                settings.stats.plannedBreaksTaken += 1
            }
            // streak: count days with breaks
            settings.stats.streakDays = max(1, settings.stats.streakDays)
        }
        isOnBreak = false
        session = nil
        canSkip = false
        canEndEarly = false
        preBreakVisible = false
        countdownVisible = false
        clearOvertime()
        SoundPlayer.playBreakEnd(settings.appearance)
        nextBreakAt = Date().addingTimeInterval(settings.breaks.workDuration)
        timeUntilNextBreak = settings.breaks.workDuration
        // Fresh per-break snooze budget for the next work cycle's pre-break warning.
        settings.stats.snoozesUsedThisCycle = 0
        recomputeSnoozesLeft()
        AutomationRunner.runAll(settings.automations, trigger: .onBreakEnd)
    }

    // MARK: - planned

    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    private func updateNextPlannedLabel(now: Date) {
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: now)
        let candidates = settings.plannedBreaks.filter { $0.enabled && $0.weekdays.contains(wd) }
            .sorted { ($0.hour*60+$0.minute) < ($1.hour*60+$1.minute) }
        let nowMins = cal.component(.hour, from: now)*60 + cal.component(.minute, from: now)
        nextPlanned = candidates.first { ($0.hour*60+$0.minute) > nowMins }
    }

    private func checkPlannedBreaks(now: Date) {
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: now)
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        let nowMins = (comps.hour ?? 0)*60 + (comps.minute ?? 0)
        for p in settings.plannedBreaks where p.enabled && p.weekdays.contains(wd) {
            let pMins = p.hour*60 + p.minute
            // Due within the last 60 seconds and not fired today
            let key = "\(p.id.uuidString)-\(dayKey(now))"
            guard !firedPlannedToday.contains(key) else { continue }
            let diffMins = nowMins - pMins
            // window: due now (0..2 min late) — if later than 10 min, skip for today
            if diffMins < 0 || diffMins > 10 { continue }
            // Away-time counts toward break: if idle covers full duration, auto-complete
            let idle = ActivityProbe.idleSeconds()
            if idle >= p.duration {
                firedPlannedToday.insert(key)
                settings.stats.plannedBreaksTaken += 1
                continue
            }
            // If busy (smart pause active), defer
            if smartPauseReason != nil {
                deferredPlanned = p
                return
            }
            firedPlannedToday.insert(key)
            // If picked up late with short window left, offer: start shortened break
            beginBreak(kind: .planned, planned: p)
            return
        }
        // prune old keys (keep set small)
        if firedPlannedToday.count > 200 { firedPlannedToday.removeAll() }
    }

    // MARK: - wellness

    private func tickWellness(now: Date, idle: TimeInterval) {
        guard idle < 15*60 else { return } // don't nudge when away
        let w = settings.wellness
        if w.postureEnabled && now >= postureNextAt {
            postureNextAt = now.addingTimeInterval(w.postureInterval)
            let msg = w.postureMessages.randomElement() ?? "Check your posture"
            lastWellnessMessage = "🧍 " + msg
            notify(title: "Posture check", body: msg)
        }
        if w.blinkEnabled && now >= blinkNextAt {
            blinkNextAt = now.addingTimeInterval(w.blinkInterval)
            let msg = w.blinkMessages.randomElement() ?? "Blink and breathe"
            lastWellnessMessage = "👁 " + msg
            notify(title: "Blink reminder", body: msg)
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Fire a wellness reminder immediately (Settings → Send test reminder).
    func testWellness(posture: Bool) {
        let w = settings.wellness
        if posture {
            let msg = w.postureMessages.randomElement() ?? "Check your posture"
            lastWellnessMessage = "🧍 " + msg
            notify(title: "Posture check", body: msg)
        } else {
            let msg = w.blinkMessages.randomElement() ?? "Blink and breathe"
            lastWellnessMessage = "👁 " + msg
            notify(title: "Blink reminder", body: msg)
        }
    }

    private func notify(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
