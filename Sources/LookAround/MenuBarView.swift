import SwiftUI

// MARK: - Menu-bar popup: Now / Stats (adaptive panel)

struct MenuBarView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @EnvironmentObject var settings: SettingsStore
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
        }
        .padding(14)
        .frame(width: 370)
        .background(Color.laPopup)
        .preferredColorScheme(settings.appearance.appTheme.colorScheme)
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

    // MARK: Now
    private var nowTab: some View {
        VStack(spacing: 10) {
            statusCard
            if scheduler.isOnBreak {
                Button("Skip break") { scheduler.skipCurrentBreak() }
                    .disabled(!scheduler.canSkip)
                    .accessibilityIdentifier("menubar.skipBreak")
                Button("End break") { scheduler.endBreakEarly() }
                    .disabled(!scheduler.canEndEarly)
                    .accessibilityIdentifier("menubar.endBreak")
            } else {
                Button("Start short break now") { scheduler.startBreakNow(kind: .short) }
                    .accessibilityIdentifier("menubar.startShortBreak")
                Button("Start long break now") { scheduler.startBreakNow(kind: .long) }
                    .accessibilityIdentifier("menubar.startLongBreak")
                Menu {
                    Button("+1 minute") { scheduler.snoozePreBreak(by: 60) }
                    Button("+5 minutes") { scheduler.snoozePreBreak(by: 300) }
                    Button("+15 minutes") { scheduler.snoozePreBreak(by: 900) }
                } label: {
                    menuLabel("Postpone next break")
                }
                .disabled(scheduler.snoozesLeft <= 0)
                .opacity(scheduler.snoozesLeft <= 0 ? 0.45 : 1)
                .accessibilityIdentifier("menubar.postponeMenu")
                Menu {
                    Button("15 minutes") { scheduler.pauseWork(for: 15*60) }
                    Button("1 hour") { scheduler.pauseWork(for: 3600) }
                    Button("Until tomorrow") { scheduler.pauseWork(for: 12*3600) }
                    if scheduler.manuallyPaused {
                        Button("Resume now") { scheduler.resumeWork() }
                    }
                } label: {
                    menuLabel(scheduler.manuallyPaused ? "Resume (paused)" : "Pause reminders")
                }
                .accessibilityIdentifier("menubar.pauseMenu")
                Button("Reset cycle") { scheduler.resetCycle() }
            }
            Divider().background(Color.laPrimaryText.opacity(0.15))
            Text("Taken \(settings.stats.shortBreaksTaken + settings.stats.longBreaksTaken + settings.stats.plannedBreaksTaken) • Skipped \(settings.stats.breaksSkipped) • Postponed \(settings.stats.breaksPostponed)")
                .font(.caption)
                .foregroundColor(.laPrimaryText.opacity(0.5))
                .accessibilityIdentifier("menubar.statsLine")
            Button("Quit LookAround") { NSApp.terminate(nil) }
                .font(.caption)
                .accessibilityIdentifier("menubar.quitButton")
        }
        .buttonStyle(.bordered)
        .tint(.laPrimaryText)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if scheduler.isOnBreak {
                Label("On break — \(TimeFmt.mmss(scheduler.session?.remaining ?? 0))", systemImage: "cup.and.saucer.fill")
                    .font(.headline).foregroundColor(.laPrimaryText)
                Text(scheduler.session?.title ?? "")
                    .font(.caption).foregroundColor(.laPrimaryText.opacity(0.6))
            } else if scheduler.manuallyPaused {
                Label("Paused — \(TimeFmt.hms(scheduler.pauseRemaining))", systemImage: "pause.circle")
                    .font(.headline).foregroundColor(.laPrimaryText)
            } else if let r = scheduler.smartPauseReason {
                Label("Waiting — \(r)", systemImage: "moon.zzz")
                    .font(.headline).foregroundColor(.laPrimaryText)
                if let t = scheduler.timeUntilNextBreak {
                    Text("Next break in \(TimeFmt.hms(t)) once you're free")
                        .font(.caption).foregroundColor(.laPrimaryText.opacity(0.6))
                }
            } else if scheduler.cooldownRemaining > 1 {
                Label("Cooling down — \(Int(scheduler.cooldownRemaining))s", systemImage: "timer")
                    .foregroundColor(.laPrimaryText)
            } else if let t = scheduler.timeUntilNextBreak {
                Label("Next break in \(TimeFmt.hms(t))", systemImage: "eye.fill")
                    .font(.headline).foregroundColor(.laPrimaryText)
                if scheduler.preBreakVisible || scheduler.countdownVisible {
                    Text("Heads up — break starting soon")
                        .font(.caption).foregroundColor(.orange)
                } else if scheduler.overtimeVisible {
                    Text("Overtime +\(TimeFmt.mmss(scheduler.overtimeElapsed)) — wrap up when ready")
                        .font(.caption).foregroundColor(.red)
                }
            } else {
                Label("Outside office hours", systemImage: "calendar")
                    .font(.headline).foregroundColor(.laPrimaryText)
            }
            if let n = scheduler.nextPlanned {
                Text("Planned: \(n.name) at \(n.timeLabel)")
                    .font(.caption).foregroundColor(.laPrimaryText.opacity(0.6))
            }
            if let w = scheduler.lastWellnessMessage {
                Text(w).font(.caption).foregroundColor(.laPrimaryText.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.laPrimaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
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
