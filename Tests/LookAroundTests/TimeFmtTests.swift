import Foundation

func registerTimeFmtTests(_ r: TestRunner) {
    r.run("TimeFmt.mmss: zero") {
        try expectEqual(TimeFmt.mmss(0), "00:00")
    }
    r.run("TimeFmt.mmss: seconds and minutes") {
        try expectEqual(TimeFmt.mmss(65), "01:05")
    }
    r.run("TimeFmt.mmss: negative clamps to zero") {
        try expectEqual(TimeFmt.mmss(-5), "00:00")
    }

    r.run("TimeFmt.hms: under an hour omits the hour component") {
        try expectEqual(TimeFmt.hms(59), "00:59")
    }
    r.run("TimeFmt.hms: over an hour includes it") {
        try expectEqual(TimeFmt.hms(3661), "1:01:01")
    }

    r.run("TimeFmt.compact: seconds only") {
        try expectEqual(TimeFmt.compact(45), "45s")
    }
    r.run("TimeFmt.compact: whole minutes") {
        try expectEqual(TimeFmt.compact(20 * 60), "20m")
    }
    r.run("TimeFmt.compact: hours and minutes") {
        try expectEqual(TimeFmt.compact(91 * 60), "1h 31m")
    }
    r.run("TimeFmt.compact: whole hour omits minutes") {
        try expectEqual(TimeFmt.compact(60 * 60), "1h")
    }
}
