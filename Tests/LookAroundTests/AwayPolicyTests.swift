import Foundation

func registerAwayPolicyTests(_ r: TestRunner) {
    let b = BreakSettings()   // 10 min work, 20 s short, 5 min long

    func decide(away: TimeInterval, idle: TimeInterval? = nil,
                kind: BreakKind = .short, settings: BreakSettings = BreakSettings(),
                credits: Bool = true) -> AwayDecision {
        AwayPolicy.decide(awaySpan: away, idleSeconds: idle ?? away,
                          upcomingKind: kind, settings: settings, creditsEnabled: credits)
    }

    r.run("Away: a short absence is ignored") {
        try expectEqual(decide(away: 30), .ignore)
    }

    r.run("Away: a minute away credits the pending short break") {
        // The default short break is 20 s, so a minute away covers it — but the
        // 60 s floor, not the 20 s duration, is what makes it count.
        try expectEqual(decide(away: 60), .credit(.short))
        try expectEqual(decide(away: 59), .ignore)
    }

    r.run("Away: a long break needs its full duration away") {
        try expectEqual(decide(away: b.longBreakDuration - 1, kind: .long), .freeze)
        try expectEqual(decide(away: b.longBreakDuration, kind: .long), .credit(.long))
    }

    r.run("Away: an uncorroborated gap freezes, never credits") {
        // Wall clock jumped an hour but the user never stopped typing: a
        // starved timer, not an absence.
        try expectEqual(decide(away: 3600, idle: 2), .freeze)
    }

    r.run("Away: credits disabled still freezes") {
        try expectEqual(decide(away: 3600, credits: false), .freeze)
        // ...and a sub-threshold absence is still ignored, not frozen.
        try expectEqual(decide(away: 10, credits: false), .ignore)
    }

    r.run("Away: threshold floors at the away minimum for tiny breaks") {
        var settings = BreakSettings()
        settings.shortBreakDuration = 5
        try expectEqual(AwayPolicy.creditThreshold(for: .short, settings: settings),
                        AwayPolicy.minimumAwaySeconds)
    }

    r.run("Away: threshold follows a long break that exceeds the minimum") {
        var settings = BreakSettings()
        settings.longBreakDuration = 15 * 60
        try expectEqual(AwayPolicy.creditThreshold(for: .long, settings: settings), 15 * 60)
    }

    r.run("Away: recorded minutes are capped so a weekend can't poison stats") {
        try expectEqual(AwayPolicy.creditedAwayMinutes(600), 10)
        try expectEqual(AwayPolicy.creditedAwayMinutes(72 * 60 * 60),
                        AwayPolicy.maxCreditedAwaySeconds / 60)
        try expectEqual(AwayPolicy.creditedAwayMinutes(-5), 0)
    }

    r.run("Away: corroboration tolerates the slack between gap and idle") {
        // The idle read happens a beat after the gap is measured, so exact
        // equality can't be required.
        try expectTrue(AwayPolicy.isCorroborated(awaySpan: 100, idleSeconds: 85))
        try expectFalse(AwayPolicy.isCorroborated(awaySpan: 100, idleSeconds: 40))
    }
}
