import Foundation
import Combine

/// Checks GitHub Releases for a newer LookAround version.
///
/// LookAround is distributed unsigned (see `packaging/homebrew/README.md`) —
/// deliberately no Sparkle/self-update dependency (this project has zero
/// external package dependencies, see `Package.swift`). So this only
/// *detects* an update and points the user at the release page; it never
/// downloads or replaces the running `.app`.
@MainActor
final class UpdateChecker: ObservableObject {
    struct ReleaseInfo: Equatable {
        let version: String   // tag with leading "v" stripped, e.g. "0.2.0"
        let url: URL          // release page (html_url), not the raw DMG asset
        let notes: String
    }

    @Published private(set) var latestRelease: ReleaseInfo?
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?

    /// The running app's own version, read from the bundle so it can never
    /// drift from what's actually installed (see `AboutPage`/`GeneralPage`,
    /// which used to hardcode "0.1.0").
    static let currentVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    private static let feedURL =
        URL(string: "https://api.github.com/repos/henryle97/look-around/releases/latest")!
    private static let dailyInterval: TimeInterval = 24 * 60 * 60

    private var dailyTimer: AnyCancellable?
    private var session: URLSession = .shared

    /// True when a fetched release is both newer than the running build and
    /// not the one the user explicitly skipped.
    func isUpdateAvailable(settings: SettingsStore) -> Bool {
        guard let release = latestRelease,
              AppVersion.isNewer(release.version, than: Self.currentVersion) else { return false }
        return release.version != settings.updates.skippedVersion
    }

    /// Starts the once-at-launch + daily background check. Safe to call once
    /// from `AppDelegate`; re-checks `settings.updates.autoCheckEnabled` on
    /// every tick so toggling it in Settings takes effect on the next cycle.
    func start(settings: SettingsStore) {
        guard dailyTimer == nil else { return }
        if settings.updates.autoCheckEnabled {
            Task { await checkNow(settings: settings) }
        }
        dailyTimer = Timer.publish(every: Self.dailyInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, settings.updates.autoCheckEnabled else { return }
                Task { await self.checkNow(settings: settings) }
            }
    }

    /// Manual "Check for Updates" entry point (About page) — runs regardless
    /// of `autoCheckEnabled`.
    func checkNow(settings: SettingsStore) async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        do {
            let (data, response) = try await session.data(from: Self.feedURL)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(GHRelease.self, from: data)
            guard let url = URL(string: release.html_url) else { throw URLError(.badURL) }
            var version = release.tag_name
            if version.hasPrefix("v") { version.removeFirst() }
            latestRelease = ReleaseInfo(version: version, url: url, notes: release.body ?? "")
        } catch {
            lastError = "Could not check for updates: \(error.localizedDescription)"
        }
        settings.updates.lastCheckedAt = Date()
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
    }
}
