import Foundation
import EventKit
import Combine

/// Detects ongoing calendar events via EventKit (permission-gated).
/// Results are cached for 60s so the 1-second scheduler tick stays cheap.
final class CalendarMonitor: ObservableObject {
    private let store = EKEventStore()
    @Published private(set) var access: AccessState = .unknown

    enum AccessState { case unknown, granted, denied }

    private var lastCheck = Date.distantPast
    private var cachedInEvent = false

    func requestAccess() {
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.access = granted ? .granted : .denied
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.access = granted ? .granted : .denied
                }
            }
        }
    }

    func refreshAccessState() {
        if #available(macOS 14, *) {
            access = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? .granted : access
        } else {
            access = EKEventStore.authorizationStatus(for: .event) == .authorized ? .granted : access
        }
    }

    /// True when any calendar event is ongoing right now.
    func isInEvent(now: Date = Date()) -> Bool {
        guard access == .granted else { return false }
        if now.timeIntervalSince(lastCheck) < 60 { return cachedInEvent }
        lastCheck = now
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60),
            calendars: nil)
        cachedInEvent = !store.events(matching: predicate).isEmpty
        return cachedInEvent
    }
}
