import SwiftUI

// MARK: - Menu-bar popup: Now / Stats (adaptive panel)

struct MenuBarView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var tab: PopupTab = .now

    enum PopupTab { case now, stats }

    var body: some View {
        VStack(spacing: 12) {
            // top bar: calendar • segmented • gear
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.laPrimaryText.opacity(0.7))
                Spacer()
                HStack(spacing: 0) {
                    segButton("Now", .now)
                        .accessibilityIdentifier("menubar.tab.now")
                    segButton("Stats", .stats)
                        .accessibilityIdentifier("menubar.tab.stats")
                }
                .padding(3)
                .background(Color.laPrimaryText.opacity(0.08), in: Capsule())
                Spacer()
                Button {
                    WindowManager.shared.openSettings(scheduler: scheduler, settings: settings)
                    // Dismiss this popover so only Settings remains on screen.
                    // MenuBarExtra offers no API for that; deactivation closes
                    // the popover, then we reactivate for the Settings window.
                    NSApp.deactivate()
                    DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.laPrimaryText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Open Settings")
                .accessibilityIdentifier("menubar.settingsButton")
            }

            if tab == .now { nowTab } else { statsTab }
            if updateChecker.isUpdateAvailable(settings: settings), let release = updateChecker.latestRelease {
                Divider().background(Color.laPrimaryText.opacity(0.15))
                Button {
                    NSWorkspace.shared.open(release.url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Update available — v\(release.version)")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.laBlue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menubar.updateAvailable")
            }
        }
        .padding(14)
        .frame(width: 370)
        .themedSurface(.popup, theme: settings.appearance.appTheme,
                       reduceTransparency: reduceTransparency)
        // The popover owns its window (and its arrow) — theme the content
        // only, never the window chrome.
        .themedChrome(theme: settings.appearance.appTheme,
                      reduceTransparency: reduceTransparency,
                      configuresWindow: false)
    }

    /// Menu labels ignore the surrounding `.tint(.laPrimaryText)` and render dim —
    /// paint them explicitly so menus read like the buttons next to them.
    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundColor(.laPrimaryText)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.laPrimaryText.opacity(0.7))
        }
    }

    private func segButton(_ title: String, _ t: PopupTab) -> some View {        Button(title) { tab = t }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tab == t ? .laPrimaryText : .laPrimaryText.opacity(0.55))
            .padding(.horizontal, 18).padding(.vertical, 5)
            .background(tab == t ? Color.laPrimaryText.opacity(0.16) : Color.clear, in: Capsule())
            .buttonStyle(.plain)
    }

    // MARK: Now — hero countdown + primary/snooze row + info cards.
    // Modeled on LookAway 2.0's Now tab (see
    // data/screenshot-blogs/2026-04-07_lookaway-20-screen-score-liquid-glass-and-more/2026-04-07-quick-look.jpg):
    // one big countdown, one primary CTA with visible snooze chips, and
    // scannable icon rows instead of a stack of equal-weight pills.
    private var nowTab: some View {
        VStack(spacing: 12) {
            heroCard
            if scheduler.isOnBreak {
                HStack(spacing: 8) {
                    Button("Skip break") { scheduler.skipCurrentBreak() }
                        .disabled(!scheduler.canSkip)
                        .accessibilityIdentifier("menubar.skipBreak")
                    Button("End break") { scheduler.endBreakEarly() }
                        .disabled(!scheduler.canEndEarly)
                        .accessibilityIdentifier("menubar.endBreak")
                }
                .buttonStyle(.bordered)
                .tint(.laPrimaryText)
            } else {
                // Primary CTA + visible snooze chips (was a hidden Menu).
                HStack(spacing: 8) {
                    Button("Start break") { scheduler.startBreakNow(kind: scheduler.upcomingKind) }
                        .accessibilityIdentifier("menubar.startBreak")
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.laPopup)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color.laPrimaryText, in: Capsule())
                    snoozeChip("+1m", 60, id: "menubar.snooze.1m")
                    snoozeChip("+5m", 300, id: "menubar.snooze.5m")
                    snoozeChip("+15m", 900, id: "menubar.snooze.15m")
                }
                // Explicit short/long entry points (kept for tests + choice).
                HStack(spacing: 16) {
                    Button("Start short break") { scheduler.startBreakNow(kind: .short) }
                        .accessibilityIdentifier("menubar.startShortBreak")
                    Button("Start long break") { scheduler.startBreakNow(kind: .long) }
                        .accessibilityIdentifier("menubar.startLongBreak")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.laPrimaryText.opacity(0.65))
                infoCards
                // Secondary row: pause / reset / quit stay available but quiet.
                HStack(spacing: 14) {
                    Menu {
                        Button("15 minutes") { scheduler.pauseWork(for: 15*60) }
                            .disabled(scheduler.pausesLeft <= 0)
                        Button("1 hour") { scheduler.pauseWork(for: 3600) }
                            .disabled(scheduler.pausesLeft <= 0)
                        Button("Until tomorrow") { scheduler.pauseWork(for: 12*3600) }
                            .disabled(scheduler.pausesLeft <= 0)
                        if scheduler.manuallyPaused {
                            Button("Resume now") { scheduler.resumeWork() }
                        }
                    } label: {
                        menuLabel(scheduler.manuallyPaused ? "Resume (paused)"
                                  : scheduler.pausesLeft <= 0 ? "Pause (none left today)" : "Pause")
                    }
                    .accessibilityIdentifier("menubar.pauseMenu")
                    Button("Reset") { scheduler.resetCycle() }
                        .accessibilityIdentifier("menubar.resetCycle")
                    Button("Quit") { NSApp.terminate(nil) }
                        .accessibilityIdentifier("menubar.quitButton")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.laPrimaryText.opacity(0.55))
            }
            Divider().background(Color.laPrimaryText.opacity(0.15))
            Text("Taken \(settings.stats.shortBreaksTaken + settings.stats.longBreaksTaken + settings.stats.plannedBreaksTaken) • Skipped \(settings.stats.breaksSkipped) • Postponed \(settings.stats.breaksPostponed)")
                .font(.caption)
                .foregroundColor(.laPrimaryText.opacity(0.5))
                .accessibilityIdentifier("menubar.statsLine")
        }
    }

    private func snoozeChip(_ title: String, _ seconds: TimeInterval, id: String) -> some View {
        Button(title) { scheduler.snoozePreBreak(by: seconds) }
            .accessibilityIdentifier(id)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.laPrimaryText.opacity(scheduler.snoozesLeft <= 0 ? 0.35 : 0.8))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .overlay(Capsule().stroke(Color.laPrimaryText.opacity(0.2), lineWidth: 1))
            .disabled(scheduler.snoozesLeft <= 0)
    }

    // MARK: hero

    private var heroCard: some View {
        VStack(spacing: 4) {
            Image(systemName: heroIcon)
                .font(.system(size: 20))
                .foregroundColor(.laPrimaryText.opacity(0.55))
            Text(heroTitle)
                .font(.system(size: 13))
                .foregroundColor(.laPrimaryText.opacity(0.65))
            Text(heroCountdown)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.laPrimaryText)
                .accessibilityIdentifier("menubar.heroCountdown")
            if let sub = heroSubline {
                Text(sub.text)
                    .font(.caption)
                    .foregroundColor(sub.color)
            }
            if let n = scheduler.nextPlanned {
                Text("Planned: \(n.name) at \(n.timeLabel)")
                    .font(.caption).foregroundColor(.laPrimaryText.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var heroIcon: String {
        if scheduler.isOnBreak { return "cup.and.saucer.fill" }
        if scheduler.manuallyPaused { return "pause.circle" }
        if scheduler.smartPauseReason != nil { return "moon.zzz" }
        if scheduler.cooldownRemaining > 1 { return "timer" }
        if scheduler.timeUntilNextBreak != nil { return "hourglass" }
        return "calendar"
    }

    private var heroTitle: String {
        if scheduler.isOnBreak { return scheduler.session?.title ?? "On break" }
        if scheduler.manuallyPaused { return "Paused" }
        if let r = scheduler.smartPauseReason { return "Waiting — \(r)" }
        if scheduler.cooldownRemaining > 1 { return "Cooling down" }
        if scheduler.timeUntilNextBreak != nil { return "Break starts in" }
        return "Outside office hours"
    }

    private var heroCountdown: String {
        if scheduler.isOnBreak { return TimeFmt.mmss(scheduler.session?.remaining ?? 0) }
        if scheduler.manuallyPaused { return TimeFmt.hms(scheduler.pauseRemaining) }
        if scheduler.cooldownRemaining > 1 { return "\(Int(scheduler.cooldownRemaining))s" }
        if let t = scheduler.timeUntilNextBreak { return TimeFmt.hms(t) }
        return "—"
    }

    private var heroSubline: (text: String, color: Color)? {
        if scheduler.isOnBreak || scheduler.manuallyPaused { return nil }
        if scheduler.preBreakVisible || scheduler.countdownVisible {
            return ("Heads up — break starting soon", .orange)
        }
        if scheduler.overtimeVisible {
            return ("Overtime +\(TimeFmt.mmss(scheduler.overtimeElapsed)) — wrap up when ready", .red)
        }
        return nil
    }

    // MARK: info cards

    private var infoCards: some View {
        VStack(spacing: 8) {
            infoRow(icon: "bolt.fill", tint: Color(red: 0.95, green: 0.65, blue: 0.15),
                    label: "Current focus time", value: focusText, valueID: "menubar.focusTime.value")
            infoRow(icon: "message.fill", tint: Color(red: 0.85, green: 0.35, blue: 0.75),
                    label: "Upcoming break", value: upcomingText, valueID: "menubar.upcomingBreak.value")
            infoRow(icon: "zzz", tint: Color.gray,
                    label: "Snoozes available", value: "\(scheduler.snoozesLeft)", valueID: "menubar.snoozesLeft.value")
        }
    }

    private var focusText: String {
        let e = scheduler.focusTimeElapsed
        if scheduler.timeUntilNextBreak == nil { return "—" }
        let mins = Int(e / 60)
        if mins < 1 { return "Just started" }
        if mins < 60 { return "\(mins) mins" }
        return TimeFmt.compact(e)
    }

    private var upcomingText: String {
        let kind = scheduler.upcomingKind == .long ? "Long" : "Short"
        return "\(kind) · \(TimeFmt.compact(scheduler.upcomingDuration))"
    }

    private func infoRow(icon: String, tint: Color, label: String, value: String, valueID: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(tint)
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.laPrimaryText.opacity(0.9))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.laPrimaryText.opacity(0.9))
                .accessibilityIdentifier(valueID)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.laPrimaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Stats
    private var statsTab: some View {
        VStack(spacing: 12) {
            // day pager pill
            HStack {
                Image(systemName: "chevron.left").foregroundColor(.laPrimaryText.opacity(0.4))
                Text("Today's Screen Score").font(.system(size: 14, weight: .semibold)).foregroundColor(.laPrimaryText)
                Image(systemName: "chevron.right").foregroundColor(.laPrimaryText.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.laPrimaryText.opacity(0.06), in: Capsule())

            // score ring
            ZStack {
                Circle()
                    .stroke(Color.laPrimaryText.opacity(0.12), style: StrokeStyle(lineWidth: 10, dash: [2, 5]))
                    .frame(width: 130, height: 130)
                Circle()
                    .trim(from: 0, to: max(0.02, scoreFraction * 0.75))
                    .stroke(AngularGradient(gradient: Gradient(colors:
                        [.pink, .purple, .orange, .yellow, .yellow]),
                        center: .center, startAngle: .degrees(135), endAngle: .degrees(135 + 270)),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: 130, height: 130)
                Text("\(score)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.laPrimaryText)
            }
            .padding(.top, 4)

            Text(scoreMessage)
                .font(.system(size: 13))
                .foregroundColor(.laPrimaryText.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.laPrimaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            statsCard(title: "Break Stats", icon: "leaf.fill", columns: true) {
                statRow(dot: .pink, label: "App breaks",
                        total: "\(appBreaks)", duration: appBreaksDuration)
                statRow(dot: .pink, label: "Natural breaks",
                        total: "\(settings.stats.naturalBreaks)",
                        duration: TimeFmt.compact(settings.stats.naturalBreakMinutes * 60))
                statRow(dot: .pink, label: "Snoozes",
                        total: "\(settings.stats.breaksPostponed)", duration: "-")
            }

            statsCard(title: "Screen Time Stats", icon: "bolt.fill", columns: false) {
                statRow(dot: .yellow, label: "Total screen time",
                        total: "", duration: TimeFmt.compact(settings.stats.screenTimeTodayMinutes * 60))
            }
        }
    }

    private var score: Int {
        let taken = settings.stats.shortBreaksTaken + settings.stats.longBreaksTaken
        let skipped = settings.stats.breaksSkipped
        guard taken + skipped > 0 else { return 100 }
        return max(35, 100 - skipped * 8)
    }
    private var scoreFraction: Double { Double(score) / 100.0 }
    private var scoreMessage: String {
        switch score {
        case 90...: return "Excellent pacing today with healthy work and rest cycles."
        case 70..<90: return "Good rhythm today — a few skipped breaks."
        default: return "Your eyes are working overtime. Try fewer skips."
        }
    }
    private var appBreaks: Int {
        settings.stats.shortBreaksTaken + settings.stats.longBreaksTaken + settings.stats.plannedBreaksTaken
    }
    private var appBreaksDuration: String {
        let secs = Double(settings.stats.shortBreaksTaken) * settings.breaks.shortBreakDuration
            + Double(settings.stats.longBreaksTaken) * settings.breaks.longBreakDuration
        return secs > 0 ? TimeFmt.compact(secs) : "-"
    }

    private func statsCard<Content: View>(title: String, icon: String, columns: Bool,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(icon == "leaf.fill"
                              ? Color(red: 0.85, green: 0.35, blue: 0.75)
                              : Color(red: 0.95, green: 0.65, blue: 0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.laPrimaryText)
                Spacer()
                if columns {
                    Text("Total").font(.caption).foregroundColor(.laPrimaryText.opacity(0.45)).frame(width: 40)
                    Text("Duration").font(.caption).foregroundColor(.laPrimaryText.opacity(0.45)).frame(width: 64, alignment: .trailing)
                } else {
                    Text("Duration").font(.caption).foregroundColor(.laPrimaryText.opacity(0.45))
                }
            }
            content()
        }
        .padding(12)
        .background(Color.laPrimaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statRow(dot: Color, label: String, total: String, duration: String) -> some View {
        HStack {
            Circle().fill(dot).frame(width: 9, height: 9)
            Text(label).font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.9))
            Spacer()
            if !total.isEmpty {
                Text(total).font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.9)).frame(width: 40)
            }
            Text(duration).font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.9))
                .frame(width: 64, alignment: .trailing)
        }
    }
}
