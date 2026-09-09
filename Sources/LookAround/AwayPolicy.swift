import Foundation

/// What an absence from the Mac means for the break cycle.
enum AwayDecision: Equatable {
    /// Too short to matter.
    case ignore
    /// Away, but not long enough to count as rest: hold the countdown.
    case freeze
    /// The absence itself was the break.
    case credit(BreakKind)
}

/// Decides whether time away from the machine — display sleep, system sleep,
/// a locked screen, or simply not touching the keyboard — counts as a break
/// already taken.
///
/// Deliberately pure (Foundation only, no scheduler/AppKit state) so the
/// standalone unit-test binary can compile it — see docs/unit-testing.md.
enum AwayPolicy {
    /// Shorter absences than this are indistinguishable from thinking.
    static let minimumAwaySeconds: TimeInterval = 60

    /// No break may fire for this long after the user comes back. The overlay
    /// landing while someone types their login password is the worst failure
    /// mode this app has, and it costs one clamp to make impossible.
    static let wakeGraceSeconds: TimeInterval = 20

    /// A weekend-long sleep shouldn't dump 4,000 "away minutes" into the stats.
    static let maxCreditedAwaySeconds: TimeInterval = 12 * 60 * 60

    /// A wall-clock gap only counts as absence if HID idle agrees. A timer
    /// starved by load or App Nap produces the same gap while the user is
    /// right there, typing.
    static let idleCorroborationRatio: Double = 0.8

    /// Time away that satisfies the break `kind` outright. Floored at
    /// `minimumAwaySeconds`: the default short break is 20 seconds, and
    /// crediting one for a 21-second absence would be theatre.
    static func creditThreshold(for kind: BreakKind, settings: BreakSettings) -> TimeInterval {
        max(minimumAwaySeconds, duration(of: kind, settings: settings))
    }

    /// Away minutes worth recording, clamped so an absurd span can't poison stats.
    static func creditedAwayMinutes(_ span: TimeInterval) -> Double {
        min(max(0, span), maxCreditedAwaySeconds) / 60
    }

    /// - Parameters:
    ///   - awaySpan: seconds the user is believed to have been away
    ///   - idleSeconds: HID idle at the moment of the decision, to corroborate `awaySpan`
    ///   - upcomingKind: the break that would have fired
    ///   - creditsEnabled: `SmartPauseSettings.idleResetsCycle`
    static func decide(
        awaySpan: TimeInterval, idleSeconds: TimeInterval,
        upcomingKind: BreakKind, settings: BreakSettings,
        creditsEnabled: Bool
    ) -> AwayDecision {
        guard awaySpan >= minimumAwaySeconds else { return .ignore }
        guard isCorroborated(awaySpan: awaySpan, idleSeconds: idleSeconds) else { return .freeze }
        guard creditsEnabled else { return .freeze }
        guard awaySpan >= creditThreshold(for: upcomingKind, settings: settings) else { return .freeze }
        return .credit(upcomingKind)
    }

    /// Whether HID idle backs up a claimed absence.
    static func isCorroborated(awaySpan: TimeInterval, idleSeconds: TimeInterval) -> Bool {
        idleSeconds >= awaySpan * idleCorroborationRatio
    }

    private static func duration(of kind: BreakKind, settings: BreakSettings) -> TimeInterval {
        switch kind {
        case .long: return settings.longBreakDuration
        case .short, .planned: return settings.shortBreakDuration
        }
    }
}
