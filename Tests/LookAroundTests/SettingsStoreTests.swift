import Foundation

func registerSettingsStoreTests(_ r: TestRunner) {
    // SettingsStore hardcodes UserDefaults.standard (see SettingsStore.swift).
    // A bare CLT binary like this test runner has its own defaults domain,
    // separate from the built .app's (keyed by bundle id com.lookaround.app),
    // but we still wipe the key before/after each test — the same precaution
    // LookAroundApp.swift's --reset-state takes before constructing a store.
    func withCleanDefaults(_ body: () throws -> Void) rethrows {
        UserDefaults.standard.removeObject(forKey: SettingsStore.persistenceKey)
        defer { UserDefaults.standard.removeObject(forKey: SettingsStore.persistenceKey) }
        try body()
    }

    r.run("SettingsStore: a fresh store has documented defaults") {
        try withCleanDefaults {
            let store = SettingsStore()
            try expectEqual(store.breaks.workDuration, 10 * 60)
            try expectEqual(store.plannedBreaks.count, 2)
            try expectFalse(store.isPaused)
        }
    }

    r.run("SettingsStore: save() then a new load() round-trips edited values") {
        try withCleanDefaults {
            let store = SettingsStore()
            store.breaks.workDuration = 45 * 60
            store.breaks.longBreakEvery = 5
            store.breaks.maxSnoozesPerBreak = 2
            store.breaks.pausesPerDay = 1
            store.wellness.blinkEnabled = false
            store.stats.shortBreaksTaken = 7
            store.stats.snoozesUsedThisCycle = 1
            store.stats.pausesUsedToday = 1
            store.save()

            let reloaded = SettingsStore()
            try expectEqual(reloaded.breaks.workDuration, 45 * 60)
            try expectEqual(reloaded.breaks.longBreakEvery, 5)
            try expectEqual(reloaded.breaks.maxSnoozesPerBreak, 2)
            try expectEqual(reloaded.breaks.pausesPerDay, 1)
            try expectFalse(reloaded.wellness.blinkEnabled)
            try expectEqual(reloaded.stats.shortBreaksTaken, 7)
            try expectEqual(reloaded.stats.snoozesUsedThisCycle, 1)
            try expectEqual(reloaded.stats.pausesUsedToday, 1)
        }
    }

    r.run("SettingsStore: resetAll() clears persistence and restores defaults") {
        try withCleanDefaults {
            let store = SettingsStore()
            store.breaks.workDuration = 999
            store.save()

            store.resetAll()
            try expectEqual(store.breaks.workDuration, 10 * 60)
            try expectNil(UserDefaults.standard.data(forKey: SettingsStore.persistenceKey))

            // Nothing left to load back.
            let reloaded = SettingsStore()
            try expectEqual(reloaded.breaks.workDuration, 10 * 60)
        }
    }
}
