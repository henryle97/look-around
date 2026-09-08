import AppKit
import Foundation

enum SoundPlayer {
    static func play(_ name: AppearanceSettings.SoundName, volume: Double = 0.7) {
        switch name {
        case .none: break
        case .chime: playSound(named: "Glass", volume: volume)
        case .rain: playSound(named: "Blow", volume: volume)
        case .forest: playSound(named: "Hero", volume: volume)
        case .waves: playSound(named: "Morse", volume: volume)
        }
    }

    /// Plays a user-picked audio file at an absolute path. Falls back to a
    /// system beep if the path is empty or the file can't be loaded.
    static func playCustom(path: String, volume: Double = 0.7) {
        guard !path.isEmpty, let s = NSSound(contentsOfFile: path, byReference: true) else {
            NSSound.beep()
            return
        }
        s.volume = Float(volume.clamped(to: 0...1))
        s.play()
    }

    /// What actually plays for one break event: a custom file if the user
    /// dropped one in, otherwise the preset style. `beginBreak`/`endBreak` in
    /// `BreakScheduler` call `playBreakStart`/`playBreakEnd`, which additionally
    /// gate on that event's on/off toggle; `SoundsPage`'s preview buttons call
    /// `previewBreakStart`/`previewBreakEnd` directly so a preview always plays
    /// even while the toggle is off.
    static func previewBreakStart(_ appearance: AppearanceSettings) {
        if !appearance.customStartSoundPath.isEmpty {
            playCustom(path: appearance.customStartSoundPath, volume: appearance.soundVolume)
        } else {
            play(appearance.soundName, volume: appearance.soundVolume)
        }
    }

    static func previewBreakEnd(_ appearance: AppearanceSettings) {
        if !appearance.customEndSoundPath.isEmpty {
            playCustom(path: appearance.customEndSoundPath, volume: appearance.soundVolume)
        } else {
            play(appearance.soundName, volume: appearance.soundVolume)
        }
    }

    static func playBreakStart(_ appearance: AppearanceSettings) {
        guard appearance.soundOnStart else { return }
        previewBreakStart(appearance)
    }

    static func playBreakEnd(_ appearance: AppearanceSettings) {
        guard appearance.soundOnEnd else { return }
        previewBreakEnd(appearance)
    }

    private static func playSound(named: String, volume: Double) {
        if let s = NSSound(named: named) {
            s.volume = Float(volume.clamped(to: 0...1))
            s.play()
        } else {
            NSSound.beep()
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
