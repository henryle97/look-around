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
