import AVFoundation
import UIKit

/// Short UI sound cues. Players are preloaded once and rewound on each play so rapid
/// PTT presses fire instantly. Cues play through the active `AVAudioSession`, so they
/// follow the same loudspeaker route as voice.
///
/// Note: the cue files ship with a `.mp3` extension but are AAC in a QuickTime
/// container — `AVAudioPlayer` decodes by content, so the extension doesn't matter.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        for name in ["start_talk", "end_talk"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[name] = player
        }
    }

    /// Cue played the moment the user starts transmitting.
    func playStartTalk() { play("start_talk") }
    /// Cue played the moment the user stops transmitting.
    func playEndTalk() { play("end_talk") }

    private func play(_ name: String) {
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }
}

/// Thin wrapper over UIKit haptics so call sites read intentfully.
@MainActor
enum Haptics {
    private static let impact: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    /// A small, short tap for an incoming text message.
    static func messageReceived() {
        impact.impactOccurred()
        impact.prepare()   // re-arm for the next one (lower latency)
    }

    private static let notify: UINotificationFeedbackGenerator = {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    /// A positive confirmation (e.g. a successful action completed).
    static func success() {
        notify.notificationOccurred(.success)
        notify.prepare()
    }

    /// Crisp tap confirming a copy-to-clipboard action.
    static func copied() {
        impact.impactOccurred()
        impact.prepare()
    }
}
