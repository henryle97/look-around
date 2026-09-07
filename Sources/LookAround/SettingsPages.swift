import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Settings pages

// ---------- General ----------

struct GeneralPage: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var launchAtLogin = false
    @State private var launchError: String? = nil
    var body: some View {
        PageHeader(icon: "gearshape.fill", title: "General", color: .laPurple)
        Card {
            SettingRow(label: "Launch at login") {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.general.launchAtLogin")
                    .onChange(of: launchAtLogin) { on in setLaunchAtLogin(on) }
            }
            CardDivider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Appearance")
                        .font(.system(size: 15))
                        .foregroundColor(.laPrimaryText)
                    Spacer()
                    // Segmented theme control: each option is a leaf button
                    // for axdrive (base id prefix + .value label). NOTE: no
                    // identifier on the HStack itself — stamping the container
                    // overrides the children's ids in practice.
                    HStack(spacing: 0) {
                        ForEach(AppearanceSettings.AppTheme.allCases) { theme in
                            Button {
                                settings.appearance.appTheme = theme
                            } label: {
                                Text(theme.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(settings.appearance.appTheme == theme
                                        ? .white : .laPrimaryText.opacity(0.6))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(settings.appearance.appTheme == theme
                                        ? Color.laBlue : Color.clear,
                                        in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.general.appTheme.\(theme.rawValue)")
                        }
                    }
                    .padding(3)
                    .background(Color.laPrimaryText.opacity(0.08), in: Capsule())
                }
                HStack {
                    Spacer()
                    Text(settings.appearance.appTheme.label)
                        .font(.system(size: 13))
                        .foregroundColor(.laPrimaryText.opacity(0.55))
                        .accessibilityIdentifier("settings.general.appTheme.value")
                }
            }
            .padding(.vertical, 10)
            CardDivider()
            SettingRow(label: "Version") {
                Text("0.1.0").foregroundColor(.laPrimaryText.opacity(0.55))
            }
            if let e = launchError {
                Text(e).font(.caption).foregroundColor(.orange)
            }
        }
        Card {
            Button("Quit LookAround") { NSApp.terminate(nil) }
                .buttonStyle(.bordered)
        }
    }
    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Could not change login item: \(error.localizedDescription)"
            launchAtLogin = !on
        }
    }
}

// ---------- Screen Breaks ----------

struct BreakPresetDef: Identifiable {
    let id = UUID()
    let name: String
    let work: TimeInterval
    let short: TimeInterval
}
private let breakPresets = [
    BreakPresetDef(name: "Balanced", work: 20*60, short: 20),
    BreakPresetDef(name: "Deep Focus", work: 45*60, short: 30),
    BreakPresetDef(name: "Eye Care", work: 15*60, short: 15),
    BreakPresetDef(name: "Wellness", work: 25*60, short: 45),
]

struct ScreenBreaksPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]

    var body: some View {
        PageHeader(icon: "leaf.fill", title: "Screen Breaks", color: .laPink)
        SectionTitle("General")
        Card {
            // Show breaks after [preset ↕] [H][M] of focused screen time
            HStack {
                Text("Show breaks after").font(.system(size: 15)).foregroundColor(.laPrimaryText)
                Spacer()
                Text(presetName).font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.8))
                Stepper("", value: presetIndex, in: 0...(breakPresets.count - 1))
                    .labelsHidden()
                    .accessibilityIdentifier("settings.screenBreaks.workIntervalPreset")
                hmBox("H", hours: workHoursBinding)
                hmBox("M", hours: workMinutesBinding)
                Text("of focused screen time").font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.8))
            }
            .padding(.vertical, 10)
            CardDivider()
            SettingRow(label: "Break duration") {
                ChipStepper(value: $settings.breaks.shortBreakDuration, range: 5...600, step: 5,
                            id: "settings.screenBreaks.breakDuration", isDurationSeconds: true) {
                    formatBreakDuration($0)
                }
            }
        }
        Card {
            navRow(icon: "wand.and.stars", title: "Customize break screen", summary: "",
                    axID: "settings.nav.customizeScreen") {
                route.append(.customizeScreen)
            }
            CardDivider()
            navRow(icon: "figure.cooldown", title: "Long breaks", summary: longSummary,
                    axID: "settings.nav.longBreaks") {
                route.append(.longBreaks)
            }
            CardDivider()
            navRow(icon: "calendar", title: "Planned breaks", summary: plannedSummary,
                    axID: "settings.nav.plannedBreaks") {
                route.append(.plannedBreaks)
            }
            CardDivider()
            navRow(icon: "clock", title: "Office hours", summary: officeSummary,
                    axID: "settings.nav.officeHours") {
                route.append(.officeHours)
            }
        }
        SectionTitle("Break enforcement")
        Card {
            HStack(spacing: 14) {
                enforcementCard(.casual, icon: "chevron.right.2", label: "Casual", sub: "Skip anytime")
                enforcementCard(.balanced, icon: "circle", label: "Balanced", sub: "Skip after a pause")
                enforcementCard(.hardcore, icon: "circle.slash", label: "Hardcore", sub: "No skips allowed")
            }
            .padding(.vertical, 12)
            CardDivider()
            SettingRow(label: "Snoozes allowed per day") {
                ChipStepper(value: $settings.breaks.snoozesPerDay, range: 0...20, step: 1,
                            id: "settings.screenBreaks.snoozesPerDay") { "\($0)" }
            }
        }
        SectionTitle("More")
        Card {
            SettingRow(label: "Double escape action on break screen") {
                Menu(settings.breaks.doubleEscapeAction.rawValue) {
                    ForEach(BreakSettings.DoubleEscapeAction.allCases) { action in
                        Button(action.rawValue) { settings.breaks.doubleEscapeAction = action }
                    }
                }
                .menuStyle(.borderlessButton)
            }
            CardDivider()
            SettingRow(label: "Let me “End break” early if nearly done") {
                Toggle("", isOn: $settings.breaks.allowEarlyEnd).labelsHidden()
            }
            CardDivider()
            SettingRow(label: "Lock my Mac automatically when a break starts") {
                Toggle("", isOn: $settings.breaks.lockMacOnBreak).labelsHidden()
            }
        }
    }

    // MARK: helpers
    private var presetName: String {
        breakPresets.first {
            $0.work == settings.breaks.workDuration && $0.short == settings.breaks.shortBreakDuration
        }?.name ?? "Custom"
    }
    private var presetIndex: Binding<Int> {
        Binding(
            get: {
                breakPresets.firstIndex {
                    $0.work == settings.breaks.workDuration && $0.short == settings.breaks.shortBreakDuration
                } ?? 0
            },
            set: {
                let p = breakPresets[$0]
                settings.breaks.workDuration = p.work
                settings.breaks.shortBreakDuration = p.short
            })
    }
    private var workHoursBinding: Binding<Int> {
        Binding(get: { Int(settings.breaks.workDuration) / 3600 },
                set: { settings.breaks.workDuration = TimeInterval($0 * 3600 + workMinutePart * 60) })
    }
    private var workMinutesBinding: Binding<Int> {
        Binding(get: { workMinutePart },
                set: { settings.breaks.workDuration = TimeInterval(workHourPart * 3600 + $0 * 60) })
    }
    private var workHourPart: Int { Int(settings.breaks.workDuration) / 3600 }
    private var workMinutePart: Int { (Int(settings.breaks.workDuration) % 3600) / 60 }

    private func formatBreakDuration(_ s: TimeInterval) -> String {
        let sec = Int(s)
        if sec < 60 { return "\(sec) seconds" }
        if sec % 60 == 0 { return "\(sec / 60) minutes" }
        return TimeFmt.compact(s).replacingOccurrences(of: "m", with: " min")
    }

    private func hmBox(_ unit: String, hours: Binding<Int>) -> some View {
        EditableHMBox(value: hours, unit: unit,
                      range: 0...(unit == "H" ? 8 : 59),
                      id: "settings.screenBreaks.work\(unit == "H" ? "Hours" : "Minutes")")
    }

    private var longSummary: String {
        guard settings.breaks.longBreakEnabled else { return "Off" }
        return "Every \(ordinal(settings.breaks.longBreakEvery)) break is \(Int(settings.breaks.longBreakDuration / 60)) mins"
    }
    private var plannedSummary: String {
        let n = settings.plannedBreaks.filter(\.enabled).count
        return n == 0 ? "Off" : (n == 1 ? "1 planned break" : "\(n) planned breaks")
    }
    private var officeSummary: String {
        guard settings.officeHours.enabled else { return "Off" }
        let days = settings.officeHours.days.count == 7 ? "everyday" : "custom days"
        return "\(hhmm(settings.officeHours.startMinutes)) to \(hhmm(settings.officeHours.endMinutes)) \(days)"
    }

    private func navRow(icon: String, title: String, summary: String, axID: String? = nil, go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.laPink.gradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(title).font(.system(size: 15)).foregroundColor(.laPrimaryText)
                Spacer()
                if !summary.isEmpty {
                    Text(summary).font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.6))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.laPrimaryText.opacity(0.35))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(axID ?? "")
    }

    private func enforcementCard(_ level: SkipDifficulty, icon: String, label: String, sub: String) -> some View {
        let selected = settings.breaks.skipDifficulty == level
        return Button { settings.breaks.skipDifficulty = level } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors:
                            [Color(red: 0.45, green: 0.25, blue: 0.55),
                             Color(red: 0.75, green: 0.32, blue: 0.35),
                             Color(red: 0.85, green: 0.45, blue: 0.20)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 120)
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                        Text("Skip Break")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.white.opacity(0.18), in: Capsule())
                }
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.laBlue : Color.clear, lineWidth: 3))
                Text(label)
                    .font(.system(size: 15, weight: selected ? .bold : .regular))
                    .foregroundColor(selected ? .laPrimaryText : .laPrimaryText.opacity(0.8))
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundColor(.laPrimaryText.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

// ---------- Long breaks ----------

struct LongBreaksPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]
    var body: some View {
        PageHeader(icon: "leaf.fill", title: "Screen Breaks", color: .laPink)
        BackButton(route: $route)
        SectionTitle("Long breaks")
        Card {
            SettingRow(label: "Enable long breaks") {
                Toggle("", isOn: $settings.breaks.longBreakEnabled).labelsHidden()
            }
            if settings.breaks.longBreakEnabled {
                CardDivider()
                SettingRow(label: "A long break every") {
                    ChipStepper(value: $settings.breaks.longBreakEvery, range: 2...10, step: 1,
                                id: "settings.longBreaks.every") {
                        "\(ordinal($0)) break"
                    }
                }
                CardDivider()
                SettingRow(label: "Long break length") {
                    ChipStepper(value: $settings.breaks.longBreakDuration, range: 60...3600, step: 60,
                                id: "settings.longBreaks.duration", isDurationSeconds: true) {
                        "\(Int($0 / 60)) mins"
                    }
                }
            }
        }
        Text("Long breaks replace the regular break when they are due and reset the short-break count.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
}

// ---------- Office hours ----------

struct OfficeHoursPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]
    var body: some View {
        PageHeader(icon: "leaf.fill", title: "Screen Breaks", color: .laPink)
        BackButton(route: $route)
        Card {
            SettingRow(label: "Show breaks only during enabled days and hours") {
                Toggle("", isOn: $settings.officeHours.enabled).labelsHidden()
                    .accessibilityIdentifier("settings.officeHours.enabled")
            }
            CardDivider()
            SettingRow(label: "Scheduling preference") {
                Text("Same schedule for all selected days")
                    .font(.system(size: 14)).foregroundColor(.laPrimaryText.opacity(0.8))
            }
        }
        SectionTitle("Schedule")
        Card {
            SettingRow(label: "Active days") {
                DayCircles(days: $settings.officeHours.days)
            }
            CardDivider()
            SettingRow(label: "Active hours") {
                HStack {
                    timeChip($settings.officeHours.startMinutes)
                    Text("to").foregroundColor(.laPrimaryText.opacity(0.6))
                    timeChip($settings.officeHours.endMinutes)
                }
            }
        }
        Text("Planned breaks run even outside office hours.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
    private func timeChip(_ minutes: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(hhmm(minutes.wrappedValue))
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundColor(.laPrimaryText)
            Stepper("", value: Binding(
                get: { minutes.wrappedValue },
                set: { minutes.wrappedValue = ((($0 % 1440) + 1440) % 1440) }
            ), in: 0...2879, step: 30).labelsHidden()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.laPrimaryText.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

// ---------- Customize break screen ----------

struct CustomizeScreenPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]
    var body: some View {
        PageHeader(icon: "leaf.fill", title: "Screen Breaks", color: .laPink)
        BackButton(route: $route)
        SectionTitle("Material")
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Break surface")
                        .font(.system(size: 15))
                        .foregroundColor(.laPrimaryText)
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(AppearanceSettings.BreakMaterial.allCases) { material in
                            Button {
                                settings.appearance.breakMaterial = material
                            } label: {
                                Text(material.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(settings.appearance.breakMaterial == material
                                        ? .white : .laPrimaryText.opacity(0.6))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(settings.appearance.breakMaterial == material
                                        ? Color.laBlue : Color.clear,
                                        in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.customizeScreen.material.\(material.rawValue)")
                        }
                    }
                    .padding(3)
                    .background(Color.laPrimaryText.opacity(0.08), in: Capsule())
                }
                HStack {
                    Spacer()
                    Text(settings.appearance.breakMaterial.label)
                        .font(.system(size: 13))
                        .foregroundColor(.laPrimaryText.opacity(0.55))
                        .accessibilityIdentifier("settings.customizeScreen.material.value")
                }
                Text("Liquid Glass uses the system glass effect on Tahoe and falls back to Frosted on older macOS.")
                    .font(.system(size: 13))
                    .foregroundColor(.laPrimaryText.opacity(0.55))
            }
            .padding(.vertical, 10)
        }
        SectionTitle("Background")
        Card {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(0..<BreakGradients.count, id: \.self) { i in
                    Button { settings.appearance.gradientIndex = i } label: {
                        LinearGradient(colors: BreakGradients[i], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 76)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(settings.appearance.gradientIndex == i ? Color.laBlue : Color.clear, lineWidth: 3))
                            .overlay(alignment: .bottomTrailing) {
                                if settings.appearance.gradientIndex == i {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white).padding(6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.customize.gradient.\(i)")
                }
            }
            .padding(.vertical, 10)
        }
        Text("The break screen blurs your wallpaper; the theme tints the frosted backdrop.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
}

// ---------- Custom messages ----------

struct CustomMessagesPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]
    var body: some View {
        PageHeader(icon: "leaf.fill", title: "Screen Breaks", color: .laPink)
        BackButton(route: $route)
        SectionTitle("Short breaks")
        Card {
            SettingRow(label: "Enable custom messages for short breaks") {
                Toggle("", isOn: $settings.appearance.shortMessagesEnabled).labelsHidden()
            }
        }
        messageList($settings.appearance.shortMessages)
        SectionTitle("Long breaks")
        Card {
            SettingRow(label: "Enable custom messages for long breaks") {
                Toggle("", isOn: $settings.appearance.longMessagesEnabled).labelsHidden()
            }
        }
        messageList($settings.appearance.longMessages)
    }

    private func messageList(_ messages: Binding<[String]>) -> some View {
        Card {
            ForEach(messages.indices, id: \.self) { i in
                if i > 0 { CardDivider() }
                TextField("Message", text: messages[i])
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.vertical, 8)
            }
            HStack {
                Button { messages.wrappedValue.append("") } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                        .background(Color.laPrimaryText.opacity(0.08), in: Circle())
                }.buttonStyle(.plain)
                Button { _ = messages.wrappedValue.popLast() } label: {
                    Image(systemName: "minus").frame(width: 30, height: 30)
                        .background(Color.laPrimaryText.opacity(0.08), in: Circle())
                }.buttonStyle(.plain)
                Spacer()
                Text("A random message from this list is shown")
                    .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.45))
            }
            .padding(.vertical, 6)
        }
    }
}

// ---------- Planned breaks ----------

struct PlannedBreaksPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]
    var body: some View {
        PageHeader(icon: "leaf.fill", title: "Screen Breaks", color: .laPink)
        HStack {
            BackButton(route: $route)
            Spacer()
            Button("Add break") { route.append(.editPlanned(nil)) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("settings.plannedBreaks.addButton")
        }
        if settings.plannedBreaks.isEmpty {
            Text("No planned breaks yet — add lunch or an afternoon walk.")
                .foregroundColor(.laPrimaryText.opacity(0.6))
        }
        Card {
            ForEach($settings.plannedBreaks) { $p in
                if p.id != settings.plannedBreaks.first?.id { CardDivider() }
                Button { route.append(.editPlanned(p.id)) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.laPrimaryText.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(Color.laPrimaryText.opacity(0.08), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(size: 15)).foregroundColor(.laPrimaryText)
                            Text("\(p.timeLabel) • \(Int(p.duration / 60)) min • \(dayLetters(p.weekdays))")
                                .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                        }
                        Spacer()
                        Toggle("", isOn: $p.enabled).labelsHidden()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.laPrimaryText.opacity(0.35))
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        Text("Planned breaks start at a fixed time, run outside office hours, and never stack with regular breaks.")
            .font(.caption).foregroundColor(.laPrimaryText.opacity(0.5))
    }
    private func dayLetters(_ days: Set<Int>) -> String {
        [2,3,4,5,6,7,1].filter(days.contains).map {
            ["?","Su","Mo","Tu","We","Th","Fr","Sa"][$0]
        }.joined(separator: " ")
    }
}

private let plannedIconChoices = [
    "fork.knife","cup.and.saucer.fill","figure.walk","leaf.fill","moon.fill",
    "eye.fill","book.fill","music.note","gamecontroller.fill","heart.fill",
    "sun.max.fill","drop.fill","bed.double.fill","bicycle","figure.run","tree.fill"
]

struct EditPlannedPage: View {
    @EnvironmentObject var settings: SettingsStore
    @Binding var route: [SettingsRoute]
    let plannedID: UUID?
    @State private var draft = PlannedBreak()
    @State private var isNew = false

    var body: some View {
        PageHeader(icon: "leaf.fill", title: plannedID == nil ? "New Planned Break" : "Edit Planned Break", color: .laPink)
        BackButton(route: $route)
        Card {
            SettingRow(label: "Enabled") {
                Toggle("", isOn: bind(\.enabled)).labelsHidden()
            }
        }
        Card {
            SettingRow(label: "Name") {
                TextField("Lunch Break", text: bind(\.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .multilineTextAlignment(.trailing)
            }
            CardDivider()
            SettingRow(label: "Starts at") {
                ChipStepper(value: startMinutes, range: 0...1435, step: 5,
                            id: "settings.plannedBreak.startTime") { hhmm($0) }
            }
            CardDivider()
            SettingRow(label: "Duration") {
                ChipStepper(value: durationMinutes, range: 1...120, step: 1,
                            id: "settings.plannedBreak.duration") {
                    $0 == 60 ? "1 hour" : ($0 < 60 ? "\($0) min" : "\(Int($0 / 60))h \($0 % 60)m")
                }
            }
            CardDivider()
            SettingRow(label: "Repeat on") {
                DayCircles(days: bind(\.weekdays))
            }
            CardDivider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Icon").font(.system(size: 15)).foregroundColor(.laPrimaryText)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 10) {
                    ForEach(plannedIconChoices, id: \.self) { icon in
                        Button { update { $0.icon = icon } } label: {
                            Image(systemName: icon)
                                .font(.system(size: 15))
                                .foregroundColor(read(\.icon) == icon ? .white : .laPrimaryText)
                                .frame(width: 38, height: 38)
                                .background(read(\.icon) == icon ? Color.laBlue : Color.laPrimaryText.opacity(0.08),
                                            in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        SectionTitle("Phone Sync")
        Card {
            SettingRow(label: "Sync this break on paired devices") {
                Toggle("", isOn: bind(\.syncToMobile)).labelsHidden()
            }
            Text("When enabled, this planned break will also start and end on paired iPhones and iPads. Push notifications still follow each device's notification settings.")
                .font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.55))
                .padding(.bottom, 10)
        }
        HStack {
            if isNew {
                Button("Save break") { saveNew() }.buttonStyle(.borderedProminent)
            } else {
                Button("Delete") { deleteExisting() }
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: draft plumbing (existing breaks edit the store live)
    private func read<T>(_ kp: KeyPath<PlannedBreak, T>) -> T {
        if !isNew, let p = settings.plannedBreaks.first(where: { $0.id == draft.id }) {
            return p[keyPath: kp]
        }
        return draft[keyPath: kp]
    }
    private func update(_ f: @escaping (inout PlannedBreak) -> Void) {
        if !isNew, let i = settings.plannedBreaks.firstIndex(where: { $0.id == draft.id }) {
            var p = settings.plannedBreaks[i]
            f(&p)
            settings.plannedBreaks[i] = p
        } else {
            f(&draft)
        }
    }
    private func bind<T>(_ kp: WritableKeyPath<PlannedBreak, T>) -> Binding<T> {
        Binding(get: { read(kp) }, set: { newVal in update { $0[keyPath: kp] = newVal } })
    }
    private var startMinutes: Binding<Int> {
        Binding(get: { read(\.hour) * 60 + read(\.minute) },
                set: { newVal in update { $0.hour = newVal / 60; $0.minute = newVal % 60 } })
    }
    private var durationMinutes: Binding<Int> {
        Binding(get: { max(1, Int(read(\.duration) / 60)) },
                set: { newVal in update { $0.duration = TimeInterval(newVal * 60) } })
    }
    private func load() {
        if let id = plannedID, let found = settings.plannedBreaks.first(where: { $0.id == id }) {
            draft = found; isNew = false
        } else {
            draft = PlannedBreak(); isNew = true
        }
    }
    private func saveNew() {
        settings.plannedBreaks.append(draft)
        route.removeLast()
    }
    private func deleteExisting() {
        settings.plannedBreaks.removeAll { $0.id == draft.id }
        route.removeLast()
    }
}
