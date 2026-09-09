import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Settings pages, part 2

// ---------- Smart Pause ----------

struct SmartPausePage: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var expanded: String? = nil
    @State private var newApp = ""
    @State private var calAccess: String = "Not requested"

    var body: some View {
        PageHeader(icon: "pause.fill", title: "Smart Pause", color: .laPink)
        Card {
            SettingRow(label: "Don’t show breaks while I’m typing or dragging") {
                Toggle("", isOn: $settings.breaks.deferWhileTyping).labelsHidden()
            }
        }
        SectionTitle("Automatically pause LookAround during")
        Card {
            pauseRow(id: "meetings", icon: "headphones",
                     title: "Meetings or Calls",
                     subtitle: "Pauses breaks during calls and online meetings",
                     isOn: $settings.smartPause.pauseOnMeetings) {
                Text("Detected when a meeting app (Zoom, Teams, Meet…) is frontmost. Chat apps like Slack are excluded — add them as deep-focus apps if you take calls there.")
                    .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                    .padding(.bottom, 8)
            }
            CardDivider()
            pauseRow(id: "video", icon: "video.fill",
                     title: "Video playback",
                     subtitle: "Pauses breaks while any video is playing",
                     isOn: $settings.smartPause.pauseOnVideo) {
                SettingRow(label: "Pause even when video plays in the background") {
                    Toggle("", isOn: $settings.smartPause.videoIncludesBackground).labelsHidden()
                }
            }
            CardDivider()
            pauseRow(id: "calendar", icon: "calendar",
                     title: "Calendar Events",
                     subtitle: "Pauses breaks when a calendar event is ongoing",
                     isOn: $settings.smartPause.pauseOnCalendarEvents) {
                HStack {
                    Text("Calendar access: \(calAccess)")
                        .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.6))
                    Spacer()
                    Button("Allow access") {
                        scheduler.calendarMonitor.requestAccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scheduler.calendarMonitor.refreshAccessState()
                            calAccess = scheduler.calendarMonitor.access == .granted ? "Granted"
                                : (scheduler.calendarMonitor.access == .denied ? "Denied" : "Not requested")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.bottom, 8)
                .onAppear {
                    scheduler.calendarMonitor.refreshAccessState()
                    calAccess = scheduler.calendarMonitor.access == .granted ? "Granted"
                        : (scheduler.calendarMonitor.access == .denied ? "Denied" : "Not requested")
                }
            }
            CardDivider()
            pauseRow(id: "focus", icon: "checkmark.circle.fill",
                     title: "Deep focus apps",
                     subtitle: "Pauses breaks when your chosen apps are active",
                     isOn: $settings.smartPause.pauseOnDeepFocus) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $settings.smartPause.deepFocusMode) {
                        ForEach(SmartPauseSettings.DeepFocusMode.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    HStack {
                        TextField("Add app (e.g. Keynote)", text: $newApp)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let t = newApp.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            settings.smartPause.deepFocusApps.append(t)
                            newApp = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    ForEach(settings.smartPause.deepFocusApps, id: \.self) { app in
                        HStack {
                            Text(app).foregroundColor(.laPrimaryText.opacity(0.85))
                            Spacer()
                            Button("Remove") {
                                settings.smartPause.deepFocusApps.removeAll { $0 == app }
                            }
                            .foregroundColor(.red)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            CardDivider()
            pauseRow(id: "gaming", icon: "gamecontroller.fill",
                     title: "Gaming",
                     subtitle: "Pauses breaks while you play fullscreen games",
                     isOn: $settings.smartPause.pauseOnGaming) {
                Text("Detected when the frontmost window fills the screen.")
                    .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                    .padding(.bottom, 8)
            }
            CardDivider()
            pauseRow(id: "focusmode", icon: "moon.fill",
                     title: "Focus Mode",
                     subtitle: "Pauses breaks while you stay fullscreen",
                     isOn: $settings.smartPause.pauseOnFocusMode) {
                Text("macOS exposes no Focus-state API, so this pauses while any app fills the screen.")
                    .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                    .padding(.bottom, 8)
            }
            CardDivider()
            HStack {
                Image(systemName: "record.circle")
                    .font(.system(size: 17))
                    .foregroundColor(.laPrimaryText.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Color.laPrimaryText.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen recording or sharing").foregroundColor(.laPrimaryText)
                    Text("Pauses breaks while a recorder is frontmost")
                        .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                }
                Spacer()
                Toggle("", isOn: $settings.smartPause.pauseOnScreenSharing).labelsHidden()
            }
            .padding(.vertical, 10)
        }
        Card {
            SettingRow(label: "Cooldown after smart pause ends") {
                ChipStepper(value: $settings.smartPause.cooldownAfterActivity,
                            range: 0...1800, step: 60,
                            id: "settings.smartPause.cooldown", isDurationSeconds: true) {
                    $0 < 60 ? "\($0)s" : (Int($0) / 60 == 1 ? "1 minute" : "\(Int($0) / 60) minutes")
                }
            }
        }
        SectionTitle("Idle Tracking")
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pause or resume LookAround when I step away")
                        .font(.system(size: 15)).foregroundColor(.laPrimaryText)
                    Spacer()
                    Text("Automatic").font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.7))
                }
                .padding(.vertical, 10)
                Text("LookAround will pause or reset timers based on your activity and settings.")
                    .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                    .padding(.bottom, 6)
            }
            CardDivider()
            SettingRow(label: "Count time away as a break taken",
                       subtitle: "Stepping away, locking the screen or closing the lid for as long as the pending break counts as having taken it.") {
                Toggle("", isOn: $settings.smartPause.idleResetsCycle).labelsHidden()
            }
        }
    }

    private func pauseRow<Options: View>(id: String, icon: String, title: String,
                                         subtitle: String, isOn: Binding<Bool>,
                                         @ViewBuilder options: () -> Options) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(.laPrimaryText.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(Color.laPrimaryText.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.laPrimaryText)
                    Text(subtitle).font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                }
                Spacer()
                Button("Options") {
                    expanded = (expanded == id) ? nil : id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Toggle("", isOn: isOn).labelsHidden()
                    .accessibilityIdentifier("settings.smartPause.\(id)")
            }
            .padding(.vertical, 10)
            if expanded == id {
                options()
                    .padding(.leading, 52)
            }
        }
    }
}

// ---------- Wellness ----------

struct WellnessPage: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var scheduler: BreakScheduler
    var body: some View {
        PageHeader(icon: "heart.fill", title: "Wellness Reminders", color: .laPink)
        Card {
            SettingRow(label: "Posture reminders",
                       subtitle: "Gentle nudges to sit tall and relax your shoulders.") {
                Toggle("", isOn: $settings.wellness.postureEnabled).labelsHidden()
            }
            if settings.wellness.postureEnabled {
                CardDivider()
                SettingRow(label: "Remind me every") {
                    ChipStepper(value: $settings.wellness.postureInterval,
                                range: 5*60...120*60, step: 5*60,
                                id: "settings.wellness.postureInterval", isDurationSeconds: true) {
                        "\(Int($0 / 60)) min"
                    }
                }
                CardDivider()
                HStack {
                    Spacer()
                    Button("Send test reminder") { scheduler.testWellness(posture: true) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.bottom, 8)
            }
        }
        Card {
            SettingRow(label: "Blink reminders",
                       subtitle: "Keep your blink rate up and follow 20-20-20.") {
                Toggle("", isOn: $settings.wellness.blinkEnabled).labelsHidden()
            }
            if settings.wellness.blinkEnabled {
                CardDivider()
                SettingRow(label: "Remind me every") {
                    ChipStepper(value: $settings.wellness.blinkInterval,
                                range: 2*60...60*60, step: 60,
                                id: "settings.wellness.blinkInterval", isDurationSeconds: true) {
                        "\(Int($0 / 60)) min"
                    }
                }
                CardDivider()
                HStack {
                    Spacer()
                    Button("Send test reminder") { scheduler.testWellness(posture: false) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.bottom, 8)
            }
        }
        Text("Reminders arrive as macOS notifications — allow them in System Settings for the full effect.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
}

// ---------- Stats (settings mirror) ----------

struct StatsSettingsPage: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        PageHeader(icon: "arrow.clockwise", title: "Stats", color: .laPink)
        Text("Today's Screen Score").font(.system(size: 17, weight: .bold)).foregroundColor(.laPrimaryText)
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.laPrimaryText.opacity(0.12), style: StrokeStyle(lineWidth: 9, dash: [2, 5]))
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: max(0.02, scoreFraction * 0.75))
                        .stroke(AngularGradient(gradient: Gradient(colors:
                            [.pink, .purple, .orange, .yellow]),
                            center: .center, startAngle: .degrees(135), endAngle: .degrees(405)),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .frame(width: 90, height: 90)
                    Text("\(score)").font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.laPrimaryText)
                }
                Text(scoreMessage).font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.7))
                Spacer()
            }
            .padding(.vertical, 8)
        }
        Card {
            miniRow(dot: .pink, label: "App breaks",
                    value: "\(appBreaks) • \(appBreaksDuration)")
            CardDivider()
            miniRow(dot: .pink, label: "Natural breaks",
                    value: "\(settings.stats.naturalBreaks) • \(TimeFmt.compact(settings.stats.naturalBreakMinutes * 60))")
            CardDivider()
            miniRow(dot: .pink, label: "Snoozes", value: "\(settings.stats.breaksPostponed)")
            CardDivider()
            miniRow(dot: .pink, label: "Skipped", value: "\(settings.stats.breaksSkipped)",
                     axID: "settings.stats.skipped")
            CardDivider()
            miniRow(dot: .yellow, label: "Total screen time today",
                    value: TimeFmt.compact(settings.stats.screenTimeTodayMinutes * 60))
        }
        HStack {
            Spacer()
            Button("Reset stats") { settings.stats = BreakStats() }
                .buttonStyle(.bordered).controlSize(.small)
            Button("Reset ALL settings") { settings.resetAll() }
                .foregroundColor(.red).buttonStyle(.bordered).controlSize(.small)
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
    private func miniRow(dot: Color, label: String, value: String, axID: String? = nil) -> some View {
        HStack {
            Circle().fill(dot).frame(width: 9, height: 9)
            Text(label).foregroundColor(.laPrimaryText)
            Spacer()
            Text(value).foregroundColor(.laPrimaryText.opacity(0.8)).monospacedDigit()
                .accessibilityIdentifier(axID ?? "")
        }
        .padding(.vertical, 8)
    }
}

// ---------- Alerts / Nudges ----------

struct AlertsPage: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var scheduler: BreakScheduler
    var body: some View {
        PageHeader(icon: "bell.badge.fill", title: "Alerts / Nudges", color: .laPink)
        SectionTitle("Positioning")
        Card {
            HStack(spacing: 14) {
                positionThumb(.topLeft, caption: "Top left")
                positionThumb(.topCenter, caption: "Top center")
                positionThumb(.topRight, caption: "Top right")
            }
            .padding(.vertical, 10)
        }
        SectionTitle("Break reminder")
        Card {
            SettingRow(label: "Show a reminder before a break appears") {
                Toggle("", isOn: $settings.breaks.preBreakWarningEnabled).labelsHidden()
            }
            CardDivider()
            HStack {
                Text("Show reminder").foregroundColor(.laPrimaryText)
                Spacer()
                ChipStepper(value: $settings.breaks.preBreakLeadTime, range: 15...600, step: 15,
                            id: "settings.alerts.preBreakLeadTime", isDurationSeconds: true) {
                    $0 < 60 ? "\($0)s" : (Int($0) / 60 == 1 ? "1 minute" : "\(Int($0) / 60) minutes")
                }
                Text("before the break starts").foregroundColor(.laPrimaryText.opacity(0.7))
            }
            .padding(.vertical, 10)
            CardDivider()
            SettingRow(label: "Keep the reminder visible for") {
                ChipStepper(value: $settings.breaks.preBreakVisibleFor, range: 1...60, step: 1,
                            id: "settings.alerts.preBreakVisibleFor", isDurationSeconds: true) {
                    Int($0) == 1 ? "1 second" : "\(Int($0)) seconds"
                }
            }
        }
        SectionTitle("Smart pause alerts")
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            alertMini("Meetings or Calls", $settings.smartPause.pauseOnMeetings)
            alertMini("Video playback", $settings.smartPause.pauseOnVideo)
            alertMini("Calendar Events", $settings.smartPause.pauseOnCalendarEvents)
            alertMini("Deep focus apps", $settings.smartPause.pauseOnDeepFocus)
            alertMini("Gaming", $settings.smartPause.pauseOnGaming)
            alertMini("Focus Mode", $settings.smartPause.pauseOnFocusMode)
        }
        HStack(alignment: .top, spacing: 14) {
            countdownCard
            overtimeCard
        }
    }

    private func positionThumb(_ pos: BreakSettings.ReminderPosition, caption: String) -> some View {
        let selected = settings.breaks.reminderPosition == pos
        return Button { settings.breaks.reminderPosition = pos } label: {
            VStack(spacing: 8) {
                ZStack(alignment: alignment(pos)) {
                    LinearGradient(colors: [Color(red: 0.55, green: 0.65, blue: 0.85),
                                            Color(red: 0.30, green: 0.45, blue: 0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 96)
                        .cornerRadius(12)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black.opacity(0.55))
                        .frame(width: pos == .topCenter ? 64 : 44, height: 20)
                        .padding(8)
                }
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.laBlue : Color.clear, lineWidth: 3))
                Text(caption)
                    .font(.system(size: 13, weight: selected ? .bold : .regular))
                    .foregroundColor(selected ? .laPrimaryText : .laPrimaryText.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
    }
    private func alignment(_ pos: BreakSettings.ReminderPosition) -> Alignment {
        switch pos {
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        }
    }

    private func alertMini(_ title: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundColor(.laPrimaryText)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .padding(14)
        .background(Color.laCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Countdown before break")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.laPrimaryText)
            ZStack {
                LinearGradient(colors: [Color(red: 0.85, green: 0.30, blue: 0.45),
                                        Color(red: 0.95, green: 0.60, blue: 0.35)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 110).cornerRadius(14)
                HStack(spacing: 8) {
                    PillIcon(systemImage: "leaf.fill")
                    Text("Starting break in 05")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: Capsule())
            }
            Text("A countdown that displays when a break is about to start")
                .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.6))
            SettingRow(label: "Enabled") {
                Toggle("", isOn: $settings.breaks.countdownEnabled).labelsHidden()
            }
            SettingRow(label: "Countdown duration") {
                ChipStepper(value: $settings.breaks.countdownDuration, range: 1...30, step: 1,
                            id: "settings.alerts.countdownDuration", isDurationSeconds: true) {
                    Int($0) == 1 ? "1 second" : "\(Int($0)) seconds"
                }
            }
        }
        .padding(14)
        .background(Color.laCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var overtimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overtime nudge")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.laPrimaryText)
            ZStack {
                LinearGradient(colors: [Color(red: 0.80, green: 0.20, blue: 0.25),
                                        Color(red: 0.90, green: 0.45, blue: 0.20)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 110).cornerRadius(14)
                HStack(spacing: 8) {
                    PillIcon(systemImage: "bolt.fill")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("45 minutes").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        Text("without a break").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: Capsule())
            }
            Text("Shows how long you've been working past your chosen screen time. Shake to dismiss.")
                .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.6))
            SettingRow(label: "Enabled") {
                Toggle("", isOn: $settings.breaks.overtimeNudgeEnabled).labelsHidden()
            }
            SettingRow(label: "Show even when paused") {
                Toggle("", isOn: $settings.breaks.overtimeShowWhenPaused).labelsHidden()
            }
        }
        .padding(14)
        .background(Color.laCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

// ---------- Lock Screen ----------

struct LockScreenPage: View {
    @AppStorage("lookaround.lock.showStatus") private var showStatus = true
    @AppStorage("lookaround.lock.liquidGlass") private var liquidGlass = true
    @AppStorage("lookaround.lock.overSaver") private var overSaver = true
    @AppStorage("lookaround.lock.offset") private var offset = 0.4
    var body: some View {
        PageHeader(icon: "lock.fill", title: "Lock Screen", color: .laPink)
        Text("Lock screen").font(.system(size: 17, weight: .bold)).foregroundColor(.laPrimaryText)
        // preview mock
        ZStack {
            LinearGradient(colors: [Color(red: 0.30, green: 0.25, blue: 0.65),
                                    Color(red: 0.15, green: 0.35, blue: 0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 220).cornerRadius(18)
            VStack(spacing: 6) {
                Text("Fri, Aug 7").font(.system(size: 15)).foregroundColor(.white.opacity(0.8))
                Text("21:52").font(.system(size: 64, weight: .semibold)).foregroundColor(.white)
                HStack(spacing: 8) {
                    Text("☕").font(.system(size: 15))
                    Text("Coffee break  •  14:40").font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.blue.opacity(0.55), in: Capsule())
            }
        }
        Card {
            SettingRow(label: "Show break status on the lock screen") {
                Toggle("", isOn: $showStatus).labelsHidden()
                    .accessibilityIdentifier("settings.lock.showStatus")
            }
            CardDivider()
            SettingRow(label: "Liquid Glass") {
                Toggle("", isOn: $liquidGlass).labelsHidden()
            }
            CardDivider()
            SettingRow(label: "Show over screen saver") {
                Toggle("", isOn: $overSaver).labelsHidden()
            }
            CardDivider()
            HStack {
                Text("Vertical offset").foregroundColor(.laPrimaryText)
                Spacer()
                Text("Default").font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.55))
            }
            .padding(.vertical, 4)
            Slider(value: $offset, in: 0...1)
                .padding(.bottom, 10)
        }
        Text("Live lock-screen status needs the LookAround system helper, which is not installed — these preferences apply once it is.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
}

// ---------- Sounds ----------

struct SoundsPage: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Group {
        PageHeader(icon: "speaker.wave.2.fill", title: "Sounds", color: .laRedOrange)
        Card {
            SettingRow(label: "Play sound when the break begins") {
                HStack(spacing: 10) {
                    previewButton(axID: "settings.sounds.begin.preview") {
                        SoundPlayer.previewBreakStart(settings.appearance)
                    }
                    Toggle("", isOn: $settings.appearance.soundOnStart).labelsHidden()
                        .accessibilityIdentifier("settings.sounds.begin.enabled")
                }
            }
            CardDivider()
            SettingRow(label: "Play sound when the break ends") {
                HStack(spacing: 10) {
                    previewButton(axID: "settings.sounds.end.preview") {
                        SoundPlayer.previewBreakEnd(settings.appearance)
                    }
                    Toggle("", isOn: $settings.appearance.soundOnEnd).labelsHidden()
                        .accessibilityIdentifier("settings.sounds.end.enabled")
                }
            }
            CardDivider()
            SettingRow(label: "Sound style") {
                Menu(settings.appearance.soundName.label) {
                    ForEach(AppearanceSettings.SoundName.allCases) { sound in
                        Button(sound.label) { settings.appearance.soundName = sound }
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(minWidth: 90)
                .accessibilityIdentifier("settings.sounds.style")
            }
            CardDivider()
            SettingRow(label: "Adjust volume") {
                Slider(value: $settings.appearance.soundVolume, in: 0...1)
                    .frame(width: 160)
                    .accessibilityIdentifier("settings.sounds.volume")
            }
        }
        Text("The style above plays for either event unless you drop in a custom sound below; turning off a toggle silences that event entirely.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))

        SectionTitle("Custom sounds")
        Card {
            HStack(alignment: .top, spacing: 12) {
                soundDropZone(label: "Start sound",
                              path: $settings.appearance.customStartSoundPath,
                              axPrefix: "settings.sounds.customStart")
                soundDropZone(label: "End sound",
                              path: $settings.appearance.customEndSoundPath,
                              axPrefix: "settings.sounds.customEnd")
            }
            .padding(.vertical, 10)
        }
        Text("Overrides the style above for that event. Best under 5 seconds — all audio formats supported.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
        }
    }

    private func previewButton(axID: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "play.circle")
                .font(.system(size: 16))
                .foregroundColor(.laPrimaryText.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(axID)
    }

    @ViewBuilder
    private func soundDropZone(label: String, path: Binding<String>, axPrefix: String) -> some View {
        if path.wrappedValue.isEmpty {
            Button { chooseSound(into: path) } label: {
                VStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Drop your audio file here…")
                        .font(.system(size: 11))
                        .foregroundColor(.laPrimaryText.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.laPrimaryText.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 92)
                .background(Color.laPrimaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .foregroundColor(.laPrimaryText.opacity(0.25)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(axPrefix).chooseButton")
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadDroppedSound(providers, into: path)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(.laPrimaryText.opacity(0.6))
                Text((path.wrappedValue as NSString).lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button {
                    SoundPlayer.playCustom(path: path.wrappedValue, volume: settings.appearance.soundVolume)
                } label: {
                    Image(systemName: "play.circle").foregroundColor(.laPrimaryText.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(axPrefix).previewButton")
                Button { path.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.laPrimaryText.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(axPrefix).removeButton")
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(Color.laPrimaryText.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func chooseSound(into path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path.wrappedValue = url.path
    }

    private func loadDroppedSound(_ providers: [NSItemProvider], into path: Binding<String>) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL? = nil
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let u = item as? URL { url = u }
            guard let picked = url else { return }
            DispatchQueue.main.async { path.wrappedValue = picked.path }
        }
        return true
    }
}

// ---------- Keyboard Shortcuts ----------

struct ShortcutsPage: View {
    var body: some View {
        PageHeader(icon: "command", title: "Keyboard Shortcuts", color: .laRedOrange)
        Card {
            shortcutRow("Start a short break now", keys: ["⌃", "⌥", "⌘", "B"])
            CardDivider()
            shortcutRow("Skip the current break", keys: ["⌃", "⌥", "⌘", "S"])
            CardDivider()
            shortcutRow("Snooze for 5 minutes", keys: ["⌃", "⌥", "⌘", "Z"])
            CardDivider()
            shortcutRow("Open settings", keys: ["⌘", ","])
        }
        Text("These work while the menu-bar panel is open. System-wide hotkeys need Accessibility access.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
        Button("Open Accessibility Settings") {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("settings.shortcuts.openAXSettings")
    }
    private func shortcutRow(_ label: String, keys: [String]) -> some View {
        HStack {
            Text(label).foregroundColor(.laPrimaryText)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { k in
                    Text(k)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.laPrimaryText.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.laPrimaryText.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// ---------- iPhone Sync ----------

struct IPhoneSyncPage: View {
    var body: some View {
        PageHeader(icon: "iphone", title: "iPhone Sync", color: .laOrange)
        Card {
            HStack {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 20)).foregroundColor(.laPrimaryText.opacity(0.7))
                VStack(alignment: .leading) {
                    Text("Not paired").font(.system(size: 15, weight: .semibold)).foregroundColor(.laPrimaryText)
                        .accessibilityIdentifier("settings.iphoneSync.status")
                    Text("No iPhone or iPad connected").font(.system(size: 13))
                        .foregroundColor(.laPrimaryText.opacity(0.55))
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("How pairing works").font(.system(size: 15, weight: .semibold)).foregroundColor(.laPrimaryText)
                Text("1. Install the LookAround companion app on your iPhone or iPad.\n2. Put both devices on the same Wi-Fi network.\n3. Enter the pairing code shown on your phone.")
                    .font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.7))
            }
            .padding(.vertical, 8)
        }
        Text("Device sync needs the companion app and a LookAround account — neither is included in this build.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
}

// ---------- Automation ----------

struct AutomationPage: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var editing: AutomationScript? = nil
    @State private var newKind: AutomationScript.Kind = .shell
    @State private var newTrigger: AutomationScript.Trigger = .onBreakStart
    var body: some View {
        PageHeader(icon: "arrow.triangle.2.circlepath", title: "Automation", color: .laOrange)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Perform actions during breaks")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.laPrimaryText)
                Text("LookAround can automatically run scripts or perform actions when your break starts or ends. Use the buttons below to add new automations.")
                    .font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.65))
            }
            .padding(.vertical, 10)
        }
        automationSection(trigger: .onBreakStart, title: "Start of break")
        automationSection(trigger: .onBreakEnd, title: "End of break")
        Text("Example: pause Spotify when a break starts and resume it when the break ends.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
        .sheet(item: $editing) { script in
            AutomationEditor(script: script) { updated in
                if let i = settings.automations.firstIndex(where: { $0.id == updated.id }) {
                    settings.automations[i] = updated
                }
                editing = nil
            } onDelete: {
                settings.automations.removeAll { $0.id == script.id }
                editing = nil
            }
            .environmentObject(settings)
            .frame(width: 440, height: 380)
            .padding()
            .background(Color.laBG)
            .preferredColorScheme(settings.appearance.appTheme.colorScheme)
        }
    }

    private func automationSection(trigger: AutomationScript.Trigger, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundColor(.laPrimaryText)
            Card {
                let items = settings.automations.filter { $0.trigger == trigger }
                if items.isEmpty {
                    Text("No automations yet.")
                        .font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.5))
                        .padding(.vertical, 8)
                }
                ForEach(items) { a in
                    Button { editing = a } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "apple.terminal")
                                .foregroundColor(.laPrimaryText.opacity(0.85))
                                .frame(width: 38, height: 38)
                                .background(Color.laPrimaryText.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).foregroundColor(.laPrimaryText)
                                Text(a.kind.rawValue).font(.system(size: 13))
                                    .foregroundColor(.laPrimaryText.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.laPrimaryText.opacity(0.35))
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.automation.row.\(a.name)")
                }
                if !items.isEmpty { CardDivider() }
                HStack {
                    Spacer()
                    Button("Add shortcut…") {
                        addNew(kind: .shortcut, trigger: trigger)
                    }
                    .buttonStyle(.bordered).controlSize(.regular)
                    Button("Add script…") {
                        addNew(kind: .shell, trigger: trigger)
                    }
                    .buttonStyle(.bordered).controlSize(.regular)
                    .accessibilityIdentifier("settings.automation.addScript")
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func addNew(kind: AutomationScript.Kind, trigger: AutomationScript.Trigger) {
        var s = AutomationScript()
        s.kind = kind; s.trigger = trigger
        s.name = kind == .shortcut ? "New shortcut" : "New script"
        s.source = kind == .shortcut ? "My Shortcut"
            : "osascript -e 'display notification \"Break started\"'"
        settings.automations.append(s)
        editing = s
    }
}

struct AutomationEditor: View {
    @State var script: AutomationScript
    var onSave: (AutomationScript) -> Void
    var onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $script.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings.automation.nameField")
            HStack {
                Picker("When", selection: $script.trigger) {
                    ForEach(AutomationScript.Trigger.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Picker("Kind", selection: $script.kind) {
                    ForEach(AutomationScript.Kind.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
            }
            Text(script.kind == .shortcut ? "Shortcut name:" : "Script source:")
                .font(.caption).foregroundColor(.laPrimaryText.opacity(0.6))
            TextEditor(text: $script.source)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .border(Color.laPrimaryText.opacity(0.15))
            HStack {
                Button("Run now") { AutomationRunner.run(script) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Delete") { onDelete() }
                    .foregroundColor(.red).buttonStyle(.bordered)
                Button("Done") { onSave(script) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("settings.automation.doneButton")
            }
        }
    }
}

// ---------- About ----------

struct AboutPage: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updateChecker: UpdateChecker

    var body: some View {
        PageHeader(icon: "info.circle.fill", title: "About", color: .laYellow)
        Card {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.laPink.gradient)
                        .frame(width: 64, height: 64)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("LookAround").font(.system(size: 20, weight: .bold)).foregroundColor(.laPrimaryText)
                    Text("Version \(UpdateChecker.currentVersion)").font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                        .accessibilityIdentifier("settings.about.version")
                    Text("A smart break reminder for your Mac.")
                        .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                }
                Spacer()
            }
            .padding(.vertical, 10)
            CardDivider()
            updatesRow
        }
        Card {
            Text("LookAround is a break reminder for your Mac. Take regular breaks to reduce eye strain.")
                .font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.7))
                .padding(.vertical, 8)
            HStack {
                Spacer()
                Button("Quit LookAround") { NSApp.terminate(nil) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var updatesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(updateStatusText)
                    .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.7))
                    .accessibilityIdentifier("settings.about.updateStatus")
                Spacer()
                Button(updateChecker.isChecking ? "Checking…" : "Check for Updates") {
                    Task { await updateChecker.checkNow(settings: settings) }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(updateChecker.isChecking)
                .accessibilityIdentifier("settings.about.checkForUpdatesButton")
            }
            if updateChecker.isUpdateAvailable(settings: settings), let release = updateChecker.latestRelease {
                HStack {
                    Button("Download v\(release.version)") { NSWorkspace.shared.open(release.url) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .accessibilityIdentifier("settings.about.downloadUpdateButton")
                    Button("Skip this version") { settings.updates.skippedVersion = release.version }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("settings.about.skipVersionButton")
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var updateStatusText: String {
        if let e = updateChecker.lastError { return e }
        if let release = updateChecker.latestRelease {
            if updateChecker.isUpdateAvailable(settings: settings) {
                return "Version \(release.version) is available."
            }
            return "You're up to date."
        }
        return "Last checked: never"
    }
}
