import Foundation
import Combine

/// Central persisted settings store. All fields Codable -> UserDefaults JSON.
final class SettingsStore: ObservableObject {
    @Published var breaks = BreakSettings()
    @Published var officeHours = OfficeHours()
    @Published var plannedBreaks: [PlannedBreak] = [
        PlannedBreak(name: "Lunch", hour: 13, minute: 0, duration: 15*60, weekdays: [2,3,4,5,6], icon: "fork.knife"),
        PlannedBreak(name: "Afternoon walk", hour: 15, minute: 30, duration: 5*60, weekdays: [2,3,4,5,6], icon: "figure.walk")
    ]
    @Published var smartPause = SmartPauseSettings()
    @Published var wellness = WellnessSettings()
    @Published var appearance = AppearanceSettings()
    @Published var automations: [AutomationScript] = []
    @Published var stats = BreakStats()
    @Published var isPaused: Bool = false
    @Published var pauseUntil: Date? = nil

    private let key = "lookaround.settings.v2"
    private var bag = Set<AnyCancellable>()

    init() {
        load()
        // Debounced autosave on any change
        Publishers.MergeMany(
            $breaks.map { _ in () }.eraseToAnyPublisher(),
            $officeHours.map { _ in () }.eraseToAnyPublisher(),
            $plannedBreaks.map { _ in () }.eraseToAnyPublisher(),
            $smartPause.map { _ in () }.eraseToAnyPublisher(),
            $wellness.map { _ in () }.eraseToAnyPublisher(),
            $appearance.map { _ in () }.eraseToAnyPublisher(),
            $automations.map { _ in () }.eraseToAnyPublisher(),
            $stats.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak self] in self?.save() }
        .store(in: &bag)
    }

    // MARK: persistence
    private struct Snapshot: Codable {
        var breaks: BreakSettings
        var officeHours: OfficeHours
        var plannedBreaks: [PlannedBreak]
        var smartPause: SmartPauseSettings
        var wellness: WellnessSettings
        var appearance: AppearanceSettings
        var automations: [AutomationScript]
        var stats: BreakStats
    }

    func save() {
        let snap = Snapshot(breaks: breaks, officeHours: officeHours, plannedBreaks: plannedBreaks,
                            smartPause: smartPause, wellness: wellness, appearance: appearance,
                            automations: automations, stats: stats)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        breaks = snap.breaks
        officeHours = snap.officeHours
        plannedBreaks = snap.plannedBreaks
        smartPause = snap.smartPause
        wellness = snap.wellness
        appearance = snap.appearance
        automations = snap.automations
        stats = snap.stats
    }

    func resetAll() {
        UserDefaults.standard.removeObject(forKey: key)
        breaks = BreakSettings()
        officeHours = OfficeHours()
        smartPause = SmartPauseSettings()
        wellness = WellnessSettings()
        appearance = AppearanceSettings()
        automations = []
        stats = BreakStats()
        plannedBreaks = []
    }
}
