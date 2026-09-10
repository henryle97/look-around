import SwiftUI
import AppKit

// MARK: - Theme plan: AppTheme mapping

extension AppearanceSettings.AppTheme {
    /// nil = follow system (no override).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        case .translucent: return .dark
        }
    }

    /// `.translucent` paints the app's own chrome with behind-window vibrancy
    /// so the desktop shows through; every other theme uses opaque fills.
    var usesVibrancy: Bool { self == .translucent }
}

// MARK: - Translucent chrome
//
// The translucent theme is deliberately a *chrome* theme: it swaps the opaque
// `laBG` / `laSide` / `laPopup` fills for an `NSVisualEffectView` backdrop plus
// a dark scrim that keeps text contrast where the wallpaper is bright. It stays
// dark in all cases (white ink over an arbitrary desktop is only legible dark),
// and Reduce Transparency drops it back to the opaque dark fills.

/// The three window-sized surfaces the app paints.
enum ThemeSurface {
    case window, sidebar, popup

    var solidFill: Color {
        switch self {
        case .window: return .laBG
        case .sidebar: return .laSide
        case .popup: return .laPopup
        }
    }

    var vibrancyMaterial: NSVisualEffectView.Material {
        switch self {
        case .window: return .underWindowBackground
        case .sidebar: return .sidebar
        case .popup: return .hudWindow
        }
    }

    /// Darkening veil over the blur — the sidebar carries the most because its
    /// rows are the smallest text in the app.
    var scrimOpacity: Double {
        switch self {
        case .window: return 0.38
        case .sidebar: return 0.48
        case .popup: return 0.34
        }
    }
}

/// Behind-window blur. Pinned to `darkAqua` because the translucent theme is
/// always dark, and these windows are plain `NSWindow`s whose appearance
/// SwiftUI's `preferredColorScheme` does not reach.
struct VibrancyBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Makes the host `NSWindow` see-through for the translucent theme, and puts
/// back exactly what it changed when the theme is switched away. Only touches a
/// window it has already modified, so the opaque themes keep whatever
/// `preferredColorScheme` set up.
final class WindowChromeView: NSView {
    var translucent = false {
        didSet { if translucent != oldValue { apply() } }
    }
    private var didMakeTranslucent = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    /// Purely a window-configuration hook — never take clicks away from the
    /// SwiftUI content it sits behind.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func apply() {
        guard let window else { return }
        if translucent {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            didMakeTranslucent = true
        } else if didMakeTranslucent {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.appearance = nil
            didMakeTranslucent = false
        }
    }
}

struct WindowChrome: NSViewRepresentable {
    let translucent: Bool
    func makeNSView(context: Context) -> NSView {
        let view = WindowChromeView()
        view.translucent = translucent
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowChromeView)?.translucent = translucent
    }
}

/// True when the surrounding chrome is showing the desktop through it — cards
/// and other inner fills need more presence over a wallpaper than over `laBG`.
private struct TranslucentSurfacesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var laTranslucentSurfaces: Bool {
        get { self[TranslucentSurfacesKey.self] }
        set { self[TranslucentSurfacesKey.self] = newValue }
    }
}

extension View {
    /// Paints one of the app's window-sized surfaces for the active theme.
    @ViewBuilder
    func themedSurface(
        _ surface: ThemeSurface,
        theme: AppearanceSettings.AppTheme,
        reduceTransparency: Bool
    ) -> some View {
        if theme.usesVibrancy && !reduceTransparency {
            self.background {
                ZStack {
                    VibrancyBackdrop(material: surface.vibrancyMaterial)
                    Color.black.opacity(surface.scrimOpacity)
                }
                .ignoresSafeArea()
            }
        } else {
            self.background(surface.solidFill)
        }
    }

    /// Applies the theme to the whole chrome of a root view: color scheme,
    /// host-window transparency, and the inner-fill environment flag.
    func themedChrome(
        theme: AppearanceSettings.AppTheme,
        reduceTransparency: Bool,
        configuresWindow: Bool = true
    ) -> some View {
        let translucent = theme.usesVibrancy && !reduceTransparency
        return self
            .preferredColorScheme(theme.colorScheme)
            .environment(\.laTranslucentSurfaces, translucent)
            .background {
                if configuresWindow {
                    WindowChrome(translucent: translucent)
                }
            }
    }

    /// Card / inset-panel fill: the standard `laCard` wash, lifted with a
    /// hairline edge when the desktop is showing through behind it.
    func cardSurface(cornerRadius: CGFloat) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

struct CardSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.laTranslucentSurfaces) private var translucent

    func body(content: Content) -> some View {
        content
            .background(
                translucent ? Color.white.opacity(0.10) : Color.laCard,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .overlay {
                if translucent {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
            }
    }
}

// MARK: - Adaptive tokens
//
// `laBG` / `laSide` / `laCard` keep their existing dark-mode values and gain
// light-mode counterparts via a dynamic NSColor provider, so every existing
// call site adapts with no per-site branching. Text and subtle fills migrate
// from hardcoded `.white` onto `laPrimaryText` (white in dark, black in
// light) — opacity levels are preserved, so
// `.white.opacity(0.55)` becomes `.laPrimaryText.opacity(0.55)` and reads
// correctly in both modes. Icon ink on saturated gradients stays `.white`
// deliberately (readable on color in either mode).

extension Color {
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }

    /// Primary text: white in dark mode, black in light mode.
    static let laPrimaryText: Color = .dynamicColor(
        light: NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0),
        dark: NSColor(white: 1.0, alpha: 1.0)
    )

    static let laBG: Color = .dynamicColor(
        light: NSColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1.0),
        dark: NSColor(red: 0.098, green: 0.106, blue: 0.133, alpha: 1.0)
    )

    static let laSide: Color = .dynamicColor(
        light: NSColor(red: 0.89, green: 0.89, blue: 0.92, alpha: 1.0),
        dark: NSColor(red: 0.066, green: 0.070, blue: 0.090, alpha: 1.0)
    )

    /// Subtle card fill: translucent white over dark, translucent black over light.
    static let laCard: Color = .dynamicColor(
        light: NSColor(white: 0.0, alpha: 0.05),
        dark: NSColor(white: 1.0, alpha: 0.045)
    )

    /// Menu-bar popup surface (was a hardcoded dark fill).
    static let laPopup: Color = .dynamicColor(
        light: NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0),
        dark: NSColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 1.0)
    )
}

// MARK: - Liquid Glass

/// Shape used by the glass/fallback background modifier.
enum GlassContainerShape {
    case capsule
    case rounded(CGFloat)
}

extension View {
    /// Liquid Glass background with graceful degradation:
    /// - `.frosted` (or any pre-Tahoe OS) keeps today's `.ultraThinMaterial`
    ///   / solid fills — no regression on macOS 13–15.
    /// - `.liquidGlass` on Tahoe+ uses `glassEffect`; Reduce Transparency
    ///   forces the opaque fallback even on Tahoe (readability requirement).
    @ViewBuilder
    func glassBackground(
        _ shape: GlassContainerShape,
        material: AppearanceSettings.BreakMaterial,
        reduceTransparency: Bool
    ) -> some View {
        if material == .liquidGlass && !reduceTransparency {
            // `glassEffect` only exists in the macOS 26 SDK (Swift 6.2+
            // toolchain); `#if compiler` keeps this compiling on older
            // toolchains, where `#available(macOS 26, *)` would still
            // reference a symbol the SDK doesn't declare at all.
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                switch shape {
                case .capsule:
                    self.glassEffect(.regular, in: Capsule())
                case .rounded(let radius):
                    self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
                }
            } else {
                switch shape {
                case .capsule:
                    self.background(.ultraThinMaterial, in: Capsule())
                case .rounded(let radius):
                    self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                }
            }
            #else
            switch shape {
            case .capsule:
                self.background(.ultraThinMaterial, in: Capsule())
            case .rounded(let radius):
                self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            }
            #endif
        } else if reduceTransparency {
            // Opaque fallback: solid dark pill/card so overlay text stays
            // readable with no translucency. The overlay stays dark cinematic
            // in all app themes by design.
            switch shape {
            case .capsule:
                self.background(Color(red: 0.16, green: 0.16, blue: 0.19), in: Capsule())
            case .rounded(let radius):
                self.background(Color(red: 0.13, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: radius))
            }
        } else {
            switch shape {
            case .capsule:
                self.background(.ultraThinMaterial, in: Capsule())
            case .rounded(let radius):
                self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            }
        }
    }

    /// Floating-pill background: today's `black.opacity(0.55)` fallback,
    /// `glassEffect` when Liquid Glass is selected and available.
    @ViewBuilder
    func floatingPillBackground(
        material: AppearanceSettings.BreakMaterial,
        reduceTransparency: Bool
    ) -> some View {
        if material == .liquidGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                self.glassEffect(.regular, in: Capsule())
            } else {
                self.background(Color.black.opacity(0.55), in: Capsule())
            }
            #else
            self.background(Color.black.opacity(0.55), in: Capsule())
            #endif
        } else if reduceTransparency {
            self.background(Color(red: 0.12, green: 0.12, blue: 0.14), in: Capsule())
        } else {
            self.background(Color.black.opacity(0.55), in: Capsule())
        }
    }

    /// Heads-up card background: today's solid dark card fallback,
    /// `glassEffect` when Liquid Glass is selected and available.
    @ViewBuilder
    func headsUpCardBackground(
        material: AppearanceSettings.BreakMaterial,
        reduceTransparency: Bool
    ) -> some View {
        if material == .liquidGlass && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            } else {
                self.background(Color(red: 0.13, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 14))
            }
            #else
            self.background(Color(red: 0.13, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 14))
            #endif
        } else {
            self.background(Color(red: 0.13, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
