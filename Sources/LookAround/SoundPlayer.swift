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
