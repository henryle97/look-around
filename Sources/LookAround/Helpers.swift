import Foundation

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

enum AppVersion {
    /// Compares two dotted version strings ("1.2.3", a leading "v" allowed).
    /// Missing/non-numeric components count as 0, so "1.2" == "1.2.0" and
    /// "1.2.3-beta" compares as "1.2.3". Returns -1/0/1 like `Comparable`.
    static func compare(_ a: String, _ b: String) -> Int {
        let lhs = components(a), rhs = components(b)
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    private static func components(_ version: String) -> [Int] {
        var v = version
        if v.hasPrefix("v") { v.removeFirst() }
        // Stop at the first non-numeric-dotted suffix (e.g. "-beta.1").
        if let dash = v.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            v = String(v[v.startIndex..<dash])
        }
        return v.split(separator: ".").map { Int($0) ?? 0 }
    }
}
