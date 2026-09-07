import SwiftUI
import AppKit

// MARK: - Break screen: blurred backdrop, clock, huge message,
// subtitle, divider, blue countdown, glass pills, snooze line

/// Tint themes for the frosted break backdrop (also used by Settings previews).
let BreakGradients: [[Color]] = [
    [.indigo, .black],
    [.teal, .black],
    [.purple, .black],
    [.green.opacity(0.9), .black],
    [.orange.opacity(0.85), .black],
    [.blue, .purple, .black],
]

/// Loads the current desktop picture with no permissions required.
/// Falls back to the last successfully loaded image, then to nil.
enum WallpaperLoader {
    private static var cacheURL: URL?
    private static var cacheImage: NSImage?

    static func load() -> NSImage? {
        let url = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        if let u = url, u == cacheURL, let img = cacheImage { return img }
        guard let u = url, let img = NSImage(contentsOf: u) else { return cacheImage }
        cacheURL = u
        cacheImage = img
        return img
    }
}

/// The real break backdrop: the user's own wallpaper, heavily blurred,
/// like a frosted-glass desktop — with gradient fallback.
struct BreakBackdrop: View {
    @State private var image: NSImage? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if let img = image, !reduceTransparency {
                GeometryReader { geo in
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 60)
                        .scaleEffect(reduceMotion ? 1.0 : 1.12)
                        .saturation(reduceMotion ? 1.0 : 1.1)
                }
            } else {
                FauxWallpaper()
            }
            // veil keeps white text readable on bright wallpapers
            Color.black.opacity(contrast == .increased ? 0.42 : 0.24)
            // vignette for depth
            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(contrast == .increased ? 0.55 : 0.38)],
                center: .center,
                startRadius: 100, endRadius: 900)
        }
        .ignoresSafeArea()
        .onAppear { image = WallpaperLoader.load() }
    }
}

/// Faux blurred-desktop backdrop used only when no wallpaper image exists.
struct FauxWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.32, green: 0.38, blue: 0.45),
                         Color(red: 0.24, green: 0.30, blue: 0.38),
                         Color(red: 0.16, green: 0.22, blue: 0.32)],
                startPoint: .top, endPoint: .bottom)
            Ellipse()
                .fill(Color(red: 0.45, green: 0.55, blue: 0.60).opacity(0.55))
                .frame(width: 900, height: 500)
                .offset(x: -320, y: -260).blur(radius: 90)
            Ellipse()
                .fill(Color(red: 0.20, green: 0.38, blue: 0.55).opacity(0.6))
                .frame(width: 800, height: 520)
                .offset(x: 340, y: 60).blur(radius: 100)
            Ellipse()
                .fill(Color(red: 0.55, green: 0.50, blue: 0.42).opacity(0.35))
                .frame(width: 700, height: 380)
                .offset(x: 40, y: -300).blur(radius: 110)
            Ellipse()
                .fill(Color(red: 0.12, green: 0.20, blue: 0.38).opacity(0.7))
                .frame(width: 900, height: 500)
                .offset(x: -100, y: 340).blur(radius: 100)
            Color.black.opacity(0.28)
        }
        .ignoresSafeArea()
    }
}

struct GlassPillButton: View {
    let title: String
    let systemImage: String
    var disabled: Bool = false
    var axID: String? = nil
    let action: () -> Void
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .glassBackground(.capsule,
                             material: settings.appearance.breakMaterial,
                             reduceTransparency: reduceTransparency)
            .overlay(Capsule().stroke(Color.white.opacity(contrast == .increased ? 0.7 : 0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(axID ?? "")
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
    }
}

struct BreakOverlayView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ZStack {
            BreakBackdrop()
            VStack(spacing: 0) {
                // live clock
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(clockString)
                }
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 72)

                Spacer()

                Text(scheduler.session?.title ?? "Take a break")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 4)
                    .padding(.horizontal, 60)

                Text(scheduler.session?.subtitle ?? "")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 2)
                    .padding(.top, 18)
                    .padding(.horizontal, 60)

                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 110, height: 2)
                    .padding(.top, 30)

                Text(TimeFmt.mmss(scheduler.session?.remaining ?? 0))
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 0.74, green: 0.87, blue: 1.0))
                    .shadow(color: Color(red: 0.45, green: 0.65, blue: 1.0).opacity(0.55), radius: 24)
                    .padding(.top, 26)

                Spacer()

                // actions
                HStack(spacing: 14) {
                    if settings.breaks.skipDifficulty != .hardcore {
                        if scheduler.canEndEarly {
                            GlassPillButton(title: "End Break", systemImage: "checkmark",
                                            axID: "break.endButton") {
                                scheduler.endBreakEarly()
                            }
                        } else {
                            GlassPillButton(title: "Skip Break", systemImage: "chevron.right.2",
                                            disabled: !scheduler.canSkip,
                                            axID: "break.skipButton") {
                                scheduler.skipCurrentBreak()
                            }
                        }
                    }
                    GlassPillButton(title: "Lock Screen", systemImage: "lock",
                                    axID: "break.lockButton") {
                        scheduler.lockScreenNow()
                    }
                }

                Text(snoozeLine)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.62, green: 0.66, blue: 0.85))
                    .padding(.top, 16)

                HStack(spacing: 6) {
                    Text("Press")
                    Text("Esc")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.white.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1))
                    Text(doubleEscapeHint)
                }
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.62, green: 0.66, blue: 0.85))
                .padding(.top, 4)
                .padding(.bottom, 54)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clockString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
    private var snoozeLine: String {
        let n = scheduler.snoozesLeft
        return n == 1 ? "1 snooze available" : "\(n) snoozes available"
    }
    private var doubleEscapeHint: String {
        switch settings.breaks.doubleEscapeAction {
        case .snooze5min: return "twice to snooze the break"
        case .skip: return "twice to skip the break"
        case .nothing: return "twice does nothing (see Settings)"
        }
    }
}

// MARK: - Heads-up reminder card (dark, top of screen)

struct PreBreakView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Almost time. Your eyes will appreciate this.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text("Starting break in \(TimeFmt.mmss(scheduler.preBreakCountdown))")
                .font(.system(size: 13, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.65))
            HStack(spacing: 8) {
                Button("Start now") { scheduler.startBreakNow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("prebreak.startNowButton")
                // Snooze + Skip all draw from the same budget, so they share
                // one disabled state — "Start now" never needs it.
                Group {
                    Button("+1m") { scheduler.snoozePreBreak(by: 60) }
                    Button("+5m") { scheduler.snoozePreBreak(by: 5*60) }
                    Button("+15m") { scheduler.snoozePreBreak(by: 15*60) }
                    Button("Skip") { scheduler.advanceSkip() }
                        .accessibilityIdentifier("prebreak.skipButton")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(scheduler.snoozesLeft <= 0)
            }
            if scheduler.snoozesLeft <= 0 {
                Text("No snoozes left")
                    .font(.caption).foregroundColor(.orange)
            }
        }
        .padding(16)
        .frame(width: 360)
        .headsUpCardBackground(material: settings.appearance.breakMaterial,
                               reduceTransparency: reduceTransparency)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(contrast == .increased ? 0.3 : 0.12), lineWidth: 1))
    }
}

// MARK: - Floating pills (cursor-following)

/// Pink squircle app-icon dot used inside the floating pills.
struct PillIcon: View {
    let systemImage: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.35, blue: 0.75),
                                              Color(red: 0.65, green: 0.25, blue: 0.80)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

struct FloatingCountdownView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        HStack(spacing: 10) {
            PillIcon(systemImage: "leaf.fill")
            Text("Starting break in \(String(format: "%02d", Int(scheduler.countdownSeconds.rounded())))")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .floatingPillBackground(material: settings.appearance.breakMaterial,
                                reduceTransparency: reduceTransparency)
        .overlay(Capsule().stroke(Color.white.opacity(contrast == .increased ? 0.4 : 0.18), lineWidth: 1))
    }
}

struct OvertimePillView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        HStack(spacing: 10) {
            PillIcon(systemImage: "bolt.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(TimeFmt.hms(scheduler.overtimeElapsed))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text("without a break")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .floatingPillBackground(material: settings.appearance.breakMaterial,
                                reduceTransparency: reduceTransparency)
        .overlay(Capsule().stroke(Color.white.opacity(contrast == .increased ? 0.4 : 0.18), lineWidth: 1))
    }
}
