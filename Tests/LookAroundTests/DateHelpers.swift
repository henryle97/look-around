import Foundation

// Deterministic date construction for tests, pinned to UTC so results
// don't depend on the host machine's time zone.
//
// Reference: 2024-01-01 is a Monday, so under Calendar's Sunday=1..Saturday=7
// weekday numbering: Mon 1 Jan = 2, Tue 2 Jan = 3, Wed 3 Jan = 4,
// Thu 4 Jan = 5, Fri 5 Jan = 6, Sat 6 Jan = 7, Sun 7 Jan = 1.

func utcCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

/// A UTC date within the 1–7 Jan 2024 reference week, at the given time.
/// `day` is the day-of-month (1...7); see the weekday table above.
func referenceDate(day: Int, hour: Int, minute: Int, calendar: Calendar = utcCalendar()) -> Date {
    var comps = DateComponents()
    comps.year = 2024
    comps.month = 1
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    return calendar.date(from: comps)!
}
