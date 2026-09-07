import Foundation

func registerOfficeHoursTests(_ r: TestRunner) {
    let cal = utcCalendar()

    r.run("OfficeHours: disabled is always active, any day/time") {
        var oh = OfficeHours()
        oh.enabled = false
        oh.days = [] // would reject every day if it were consulted
        try expectTrue(oh.isActive(at: referenceDate(day: 1, hour: 3, minute: 0), calendar: cal))
    }

    r.run("OfficeHours: enabled, day not in `days` -> inactive") {
        var oh = OfficeHours()
        oh.enabled = true
        oh.days = [3, 4, 5, 6, 7] // Tue...Sat — excludes Monday (1 Jan, weekday 2)
        oh.startMinutes = 0
        oh.endMinutes = 24 * 60 - 1
        try expectFalse(oh.isActive(at: referenceDate(day: 1, hour: 10, minute: 0), calendar: cal))
    }

    r.run("OfficeHours: same-day window — inside is active") {
        var oh = OfficeHours()
        oh.enabled = true
        oh.days = [2] // Monday
        oh.startMinutes = 9 * 60
        oh.endMinutes = 17 * 60
        try expectTrue(oh.isActive(at: referenceDate(day: 1, hour: 12, minute: 0), calendar: cal))
    }

    r.run("OfficeHours: same-day window — before start is inactive") {
        var oh = OfficeHours()
        oh.enabled = true
        oh.days = [2]
        oh.startMinutes = 9 * 60
        oh.endMinutes = 17 * 60
        try expectFalse(oh.isActive(at: referenceDate(day: 1, hour: 8, minute: 59), calendar: cal))
    }

    r.run("OfficeHours: same-day window — start minute is inclusive") {
        var oh = OfficeHours()
        oh.enabled = true
        oh.days = [2]
        oh.startMinutes = 9 * 60
        oh.endMinutes = 17 * 60
        try expectTrue(oh.isActive(at: referenceDate(day: 1, hour: 9, minute: 0), calendar: cal))
    }

    r.run("OfficeHours: same-day window — end minute is exclusive") {
        var oh = OfficeHours()
        oh.enabled = true
        oh.days = [2]
        oh.startMinutes = 9 * 60
        oh.endMinutes = 17 * 60
        try expectFalse(oh.isActive(at: referenceDate(day: 1, hour: 17, minute: 0), calendar: cal))
    }

    r.run("OfficeHours: overnight window wraps past midnight") {
        var oh = OfficeHours()
        oh.enabled = true
        oh.days = [1, 2, 3, 4, 5, 6, 7]
        oh.startMinutes = 22 * 60 // 22:00
        oh.endMinutes = 2 * 60    // 02:00 next day
        try expectTrue(oh.isActive(at: referenceDate(day: 1, hour: 23, minute: 0), calendar: cal),
                        "23:00 should be inside 22:00-02:00")
        try expectTrue(oh.isActive(at: referenceDate(day: 1, hour: 1, minute: 30), calendar: cal),
                        "01:30 should be inside 22:00-02:00")
        try expectFalse(oh.isActive(at: referenceDate(day: 1, hour: 12, minute: 0), calendar: cal),
                         "midday should be outside an overnight 22:00-02:00 window")
    }
}
