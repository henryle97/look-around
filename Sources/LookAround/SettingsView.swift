import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Sidebar settings (adaptive: follows AppTheme)
//
// Adaptive surfaces (laBG/laSide/laCard/laPopup/laPrimaryText) live in
// Theme.swift as dynamic colors. Accent colors below stay fixed — they are
// icon gradients, readable with white ink in either mode.

extension Color {
    static let laPink = Color(red: 0.84, green: 0.36, blue: 0.70)
    static let laPurple = Color(red: 0.62, green: 0.42, blue: 0.88)
    static let laOrange = Color(red: 0.90, green: 0.55, blue: 0.25)
    static let laRedOrange = Color(red: 0.90, green: 0.38, blue: 0.30)
    static let laYellow = Color(red: 0.80, green: 0.66, blue: 0.20)
    static let laBlue = Color(red: 0.20, green: 0.48, blue: 1.0)
}

enum SettingsRoute: Hashable {
    case general
    case screenBreaks, longBreaks, officeHours, customizeScreen, customMessages
    case plannedBreaks, editPlanned(UUID?) // nil = new
    case smartPause, wellness, stats
    case alerts, lockScreen, sounds, shortcuts
    case iphoneSync, automation, about

    /// Stable slug for sidebar-row accessibility identifiers (`settings.nav.<slug>`).
    var navSlug: String {
        switch self {
        case .general: return "general"
        case .screenBreaks: return "screenBreaks"
        case .longBreaks: return "longBreaks"
        case .officeHours: return "officeHours"
        case .customizeScreen: return "customizeScreen"
        case .customMessages: return "customMessages"
        case .plannedBreaks: return "plannedBreaks"
        case .editPlanned: return "editPlanned"
        case .smartPause: return "smartPause"
        case .wellness: return "wellness"
        case .stats: return "stats"
        case .alerts: return "alerts"
        case .lockScreen: return "lockScreen"
        case .sounds: return "sounds"
        case .shortcuts: return "shortcuts"
        case .iphoneSync: return "iphoneSync"
        case .automation: return "automation"
        case .about: return "about"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var route: [SettingsRoute]

    init(initial: [SettingsRoute] = [.screenBreaks]) {
        _route = State(initialValue: initial)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)
                .background(Color.laSide)
            Divider().background(Color.laPrimaryText.opacity(0.08))
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.laBG)
        }
        .frame(minWidth: 940, minHeight: 700)
        .preferredColorScheme(settings.appearance.appTheme.colorScheme)
        .accessibilityIdentifier("settings.window")
    }

    // MARK: sidebar
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sideRow(icon: "gearshape.fill", title: "General", color: .laPurple, route: .general)
                    .padding(.top, 14)
                sideHeader("Focus & Wellbeing")
                sideRow(icon: "leaf.fill", title: "Screen Breaks", color: .laPink, route: .screenBreaks)
                sideRow(icon: "pause.fill", title: "Smart Pause", color: .laPink, route: .smartPause)
                sideRow(icon: "heart.fill", title: "Wellness Reminders", color: .laPink, route: .wellness)
                sideRow(icon: "arrow.clockwise", title: "Stats", color: .laPink, route: .stats)
                sideHeader("Behavior & Feedback")
                sideRow(icon: "bell.badge.fill", title: "Alerts / Nudges", color: .laPink, route: .alerts)
                sideRow(icon: "lock.fill", title: "Lock Screen", color: .laPink, route: .lockScreen)
                sideRow(icon: "speaker.wave.2.fill", title: "Sounds", color: .laRedOrange, route: .sounds)
                sideRow(icon: "command", title: "Keyboard Shortcuts", color: .laRedOrange, route: .shortcuts)
                sideHeader("Integrations")
                sideRow(icon: "iphone", title: "iPhone Sync", color: .laOrange, route: .iphoneSync)
                sideRow(icon: "arrow.triangle.2.circlepath", title: "Automation", color: .laOrange, route: .automation)
                sideHeader("LookAround")
                sideRow(icon: "info.circle.fill", title: "About", color: .laYellow, route: .about)
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 10)
        }
    }

    private func sideHeader(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.laPrimaryText.opacity(0.42))
            .padding(.top, 16).padding(.bottom, 4).padding(.leading, 10)
    }

    private func sideRow(icon: String, title: String, color: Color, route r: SettingsRoute) -> some View {
        let selected = route.first == r
            || (r == .screenBreaks && [.longBreaks, .officeHours, .customizeScreen, .customMessages, .plannedBreaks].contains(route.first))
        return Button {
            route = [r]
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.gradient)
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.laPrimaryText.opacity(selected ? 1 : 0.88))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Color.laPrimaryText.opacity(0.09) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.nav.\(r.navSlug)")
    }

    // MARK: detail
    @ViewBuilder
    private var detail: some View {
        let current = route.last ?? .screenBreaks
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch current {
                case .general: GeneralPage()
                case .screenBreaks: ScreenBreaksPage(route: $route)
                case .longBreaks: LongBreaksPage(route: $route)
                case .officeHours: OfficeHoursPage(route: $route)
                case .customizeScreen: CustomizeScreenPage(route: $route)
                case .customMessages: CustomMessagesPage(route: $route)
                case .plannedBreaks: PlannedBreaksPage(route: $route)
                case .editPlanned(let id): EditPlannedPage(route: $route, plannedID: id)
                case .smartPause: SmartPausePage()
                case .wellness: WellnessPage()
                case .stats: StatsSettingsPage()
                case .alerts: AlertsPage()
                case .lockScreen: LockScreenPage()
                case .sounds: SoundsPage()
                case .shortcuts: ShortcutsPage()
                case .iphoneSync: IPhoneSyncPage()
                case .automation: AutomationPage()
                case .about: AboutPage()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environmentObject(settings)
        .environmentObject(scheduler)
    }
}

// MARK: - shared components

struct PageHeader: View {
    let icon: String
    let title: String
    let color: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.gradient)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.laPrimaryText)
        }
    }
}

struct BackButton: View {
    @Binding var route: [SettingsRoute]
    var body: some View {
        Button {
            if route.count > 1 { route.removeLast() } else { route = [.screenBreaks] }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                Text("Back").font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.laPrimaryText.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .overlay(Capsule().stroke(Color.laPrimaryText.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.laPrimaryText)
            .padding(.top, 6)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(Color.laCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CardDivider: View {
    var body: some View {
        Divider().background(Color.laPrimaryText.opacity(0.09))
            .padding(.vertical, 2)
    }
}

/// A settings row: label left, control right.
struct SettingRow<Control: View>: View {
    let label: String
    var subtitle: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(.laPrimaryText)
                if let s = subtitle {
                    Text(s)
                        .font(.system(size: 13))
                        .foregroundColor(.laPrimaryText.opacity(0.55))
                }
            }
            Spacer()
            control
        }
        .padding(.vertical, 10)
    }
}

/// Numeric types `ChipStepper`/`EditableHMBox` can edit as free text: needs
/// a lossless round-trip through `Double` for range-clamping and (for
/// `TimeInterval` fields) second↔minute conversion while editing.
protocol ChipStepperNumeric: Strideable {
    var doubleValue: Double { get }
    init(clamped d: Double)
}
extension Int: ChipStepperNumeric {
    var doubleValue: Double { Double(self) }
    init(clamped d: Double) { self = Int(d.rounded()) }
}
extension Double: ChipStepperNumeric {
    var doubleValue: Double { self }
    init(clamped d: Double) { self = d }
}

/// Dark chip + stepper, e.g. "45 seconds ↕", where the number is also
/// directly editable: click it to type a value; Return or clicking away
/// commits it (clamped to `range`).
///
/// `id` is a stable accessibility identifier for UI-test/agent drivers
/// (see AGENTS.md): the displayed value carries `"\(id).value"` (readable
/// via AXValue, clickable to start editing) and the stepper control itself
/// carries `id` (drivable via the AX increment/decrement actions).
///
/// `isDurationSeconds` marks a `TimeInterval` stored in seconds but shown
/// in minutes once it reaches a whole minute (matching `format`'s own
/// second/minute switch): editing then happens in whichever unit is
/// currently displayed, so what you type matches what you saw.
struct ChipStepper<V: ChipStepperNumeric>: View {
    @Binding var value: V
    var range: ClosedRange<V>
    var step: V.Stride
    var id: String
    var isDurationSeconds: Bool = false
    var format: (V) -> String

    @State private var isEditing = false
    @State private var text = ""
    @State private var editUnitIsMinutes = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // NB: the "\(id).value" identifier is applied to just the
            // TextField/Text leaf, never to a container that also holds the
            // "sec"/"min" indicator — a shared container identifier gets
            // stamped onto every leaf inside it, making lookups ambiguous.
            if isEditing {
                HStack(spacing: 3) {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .frame(width: 34)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.laPrimaryText)
                        .focused($isFocused)
                        .onSubmit(commit)
                        .onExitCommand { isEditing = false }
                        .onChange(of: text) { text = $0.filter(\.isNumber) }
                        .accessibilityIdentifier("\(id).value")
                    if isDurationSeconds {
                        Text(editUnitIsMinutes ? "min" : "sec")
                            .font(.system(size: 12)).foregroundColor(.laPrimaryText.opacity(0.5))
                    }
                }
            } else {
                Text(format(value))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.laPrimaryText)
                    .onTapGesture(perform: beginEditing)
                    .accessibilityAction(.default, beginEditing)
                    .accessibilityIdentifier("\(id).value")
            }
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .accessibilityIdentifier(id)
        }
        .onChange(of: isFocused) { focused in
            if !focused && isEditing { commit() }
        }
    }

    private func beginEditing() {
        let seconds = value.doubleValue
        editUnitIsMinutes = isDurationSeconds && seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0
        text = "\(Int(editUnitIsMinutes ? seconds / 60 : seconds))"
        isEditing = true
        isFocused = true
    }

    private func commit() {
        if let n = Double(text) {
            let raw = n * (editUnitIsMinutes ? 60 : 1)
            let clamped = min(max(raw, range.lowerBound.doubleValue), range.upperBound.doubleValue)
            value = V(clamped: clamped)
        }
        isEditing = false
    }
}

/// Dark chip + stepper for a plain integer, e.g. "3 H ↕", where the number
/// itself is also directly editable: click it to type a value; Return or
/// clicking away commits it (clamped to `range`).
///
/// `id` follows the same convention as `ChipStepper`: the displayed number
/// carries `"\(id).value"`, the stepper control carries `id`.
struct EditableHMBox: View {
    @Binding var value: Int
    var unit: String
    var range: ClosedRange<Int>
    var id: String

    @State private var isEditing = false
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if isEditing {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 26)
                        .focused($isFocused)
                        .onSubmit(commit)
                        .onExitCommand { isEditing = false }
                        .onChange(of: text) { text = $0.filter(\.isNumber) }
                } else {
                    Text("\(value)")
                        .onTapGesture(perform: beginEditing)
                        .accessibilityAction(.default, beginEditing)
                        .frame(minWidth: 22, alignment: .trailing)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.laPrimaryText)
            .accessibilityIdentifier("\(id).value")
            Text(unit).font(.system(size: 13)).foregroundColor(.laPrimaryText.opacity(0.5))
            Stepper("", value: $value, in: range).labelsHidden().accessibilityIdentifier(id)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.laPrimaryText.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: isFocused) { focused in
            if !focused && isEditing { commit() }
        }
    }

    private func beginEditing() {
        text = "\(value)"
        isEditing = true
        isFocused = true
    }

    private func commit() {
        if let n = Int(text) {
            value = min(max(n, range.lowerBound), range.upperBound)
        }
        isEditing = false
    }
}

/// Blue day circles, Monday-first.
struct DayCircles: View {
    @Binding var days: Set<Int>
    private let order = [(2,"M"),(3,"T"),(4,"W"),(5,"T"),(6,"F"),(7,"S"),(1,"S")]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(order, id: \.0) { d in
                Button {
                    if days.contains(d.0) { days.remove(d.0) } else { days.insert(d.0) }
                } label: {
                    Text(d.1)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(days.contains(d.0) ? .white : .laPrimaryText.opacity(0.5))
                        .frame(width: 30, height: 30)
                        .background(days.contains(d.0) ? Color.laBlue : Color.laPrimaryText.opacity(0.08),
                                    in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

func hhmm(_ minutes: Int) -> String {
    let m = ((minutes % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
}

func ordinal(_ n: Int) -> String {
    switch n % 10 {
    case 1 where n % 100 != 11: return "\(n)st"
    case 2 where n % 100 != 12: return "\(n)nd"
    case 3 where n % 100 != 13: return "\(n)rd"
    default: return "\(n)th"
    }
}
