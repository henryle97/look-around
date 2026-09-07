import Foundation

// MARK: - Break-prompt selection
//
// Weighted random pick over a `[BreakPrompt]` pool that avoids immediate
// repeats and, where an alternative exists, avoids repeating the category
// shown last time — so an eye-break pool doesn't say "blink" three times
// running. Pure/deterministic given its inputs, so it's unit-testable
// without touching BreakScheduler's timer/state machine.
enum PromptPicker {
    /// Prompts eligible for the *next* pick: recently-shown ids are
    /// excluded first (falling back to the full pool if nothing would be
    /// left), then prompts sharing `lastCategory` are excluded where an
    /// alternative category exists.
    static func candidates(from pool: [BreakPrompt], recentIDs: [String], lastCategory: PromptCategory?) -> [BreakPrompt] {
        guard !pool.isEmpty else { return [] }
        let unseen = pool.filter { !recentIDs.contains($0.id) }
        let notRecentlyShown = unseen.isEmpty ? pool : unseen
        guard let lastCategory else { return notRecentlyShown }
        let differentCategory = notRecentlyShown.filter { $0.category != lastCategory }
        return differentCategory.isEmpty ? notRecentlyShown : differentCategory
    }

    /// Picks one prompt from `pool`, weighted by `BreakPrompt.weight`
    /// (non-positive weights count as 1). `randomIndex` defaults to real
    /// randomness; tests inject a fixed index to make the pick deterministic.
    static func pick(
        from pool: [BreakPrompt], recentIDs: [String], lastCategory: PromptCategory?,
        randomIndex: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) -> BreakPrompt? {
        let pickFrom = candidates(from: pool, recentIDs: recentIDs, lastCategory: lastCategory)
        guard !pickFrom.isEmpty else { return nil }
        let totalWeight = pickFrom.reduce(0) { $0 + max(1, $1.weight) }
        var roll = randomIndex(0..<totalWeight)
        for p in pickFrom {
            let w = max(1, p.weight)
            if roll < w { return p }
            roll -= w
        }
        return pickFrom.last
    }
}

enum TimeFmt {
    static func mmss(_ interval: TimeInterval) -> String {
        let t = max(0, Int(interval.rounded()))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
    static func hms(_ interval: TimeInterval) -> String {
        let t = max(0, Int(interval.rounded()))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
    /// Compact stats style: "45s", "20m", "1h 31m".
    static func compact(_ interval: TimeInterval) -> String {
        let t = max(0, Int(interval.rounded()))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
