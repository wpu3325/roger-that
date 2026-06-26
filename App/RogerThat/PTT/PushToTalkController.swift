import Foundation
import PushToTalk
import RogerThatCore

/// HUMAN: PushToTalk framework requires:
///   1. com.apple.developer.push-to-talk entitlement (enable in Apple Developer portal).
///   2. A VoIP push certificate (APNs) — the background-wake on incoming TALK_START
///      uses a push notification to bring the app to life.
///   3. NSMicrophoneUsageDescription in Info.plist.
///
/// NOTE: Background wake is best-effort when offline (no APNs path). In fully
/// offline mesh scenarios the app must already be in the foreground.

final class PushToTalkController: NSObject {

    // MARK: - Public API

    var onFloorStateChange: ((FloorState) -> Void)?

    func startTalking() {
        guard !isTalking else { return }
        isTalking = true
        onFloorStateChange?(.talkingLocal)

        // The on-screen button's gesture (hold + tap-to-toggle) runs on the main actor,
        // so cueing here is safe.
        MainActor.assumeIsolated { SoundEffects.shared.playStartTalk() }

        sendTalkStart()
        try? audioEngine.startCapture()

        audioEngine.onEncodedFrame = { [weak self] frame in
            self?.sendVoiceFrame(frame)
        }
    }

    func stopTalking() {
        guard isTalking else { return }
        isTalking = false
        onFloorStateChange?(.idle)

        MainActor.assumeIsolated { SoundEffects.shared.playEndTalk() }

        audioEngine.stopCapture()
        sendTalkEnd()
        // The voice link stays up for the whole channel session (managed by AppState),
        // so peers remain connected and can hear the next person who talks.
    }

    // MARK: - Init

    init(localID: UInt32, channelIDHash: UInt32, crypto: ChannelCrypto,
         voiceLink: MultipeerVoiceLink, audioEngine: AudioEngineIO) {
        self.localID = localID
        self.channelIDHash = channelIDHash
        self.crypto = crypto
        self.voiceLink = voiceLink
        self.audioEngine = audioEngine
        super.init()
        setupPTTChannel()
    }

    // MARK: - Private

    private let localID: UInt32
    /// Real channel hash stamped on every voice/talk packet so peers can drop cross-channel
    /// traffic (was `0` before — the bleed that let two channels hear each other).
    private let channelIDHash: UInt32
    /// Seals voice frames with the channel key (the Multipeer path skips FloodRouter's crypto).
    private let crypto: ChannelCrypto
    private let voiceLink: MultipeerVoiceLink
    private let audioEngine: AudioEngineIO
    private var isTalking = false
    private var talkSessionID: UInt32 = 0
    private var voiceSeq: UInt32 = 0

    private func sendTalkStart() {
        talkSessionID = UInt32.random(in: .min ... .max)
        voiceSeq = 0
        var idBytes = talkSessionID.bigEndian
        let body = Data(bytes: &idBytes, count: 4)
        let pkt = Packet(type: .talkStart, channelIDHash: channelIDHash,
                         senderID: localID, messageID: UInt64.random(in: .min ... .max), body: body)
        if let data = try? PacketCodec.encode(pkt) { voiceLink.broadcast(data) }
    }

    private func sendTalkEnd() {
        var idBytes = talkSessionID.bigEndian
        let body = Data(bytes: &idBytes, count: 4)
        let pkt = Packet(type: .talkEnd, channelIDHash: channelIDHash,
                         senderID: localID, messageID: UInt64.random(in: .min ... .max), body: body)
        if let data = try? PacketCodec.encode(pkt) { voiceLink.broadcast(data) }
    }

    private func sendVoiceFrame(_ frame: Data) {
        let seq = voiceSeq
        voiceSeq += 1
        // Seal [sessionID][seq][frame] with the channel key so only members can play it.
        guard let body = try? VoiceBody.seal(sessionID: talkSessionID, seq: seq,
                                             frame: frame, crypto: crypto) else { return }
        let pkt = Packet(type: .voiceFrame, flags: .bodyEncrypted, channelIDHash: channelIDHash,
                         senderID: localID, messageID: UInt64.random(in: .min ... .max), body: body)
        if let data = try? PacketCodec.encode(pkt) { voiceLink.broadcast(data) }
    }

    private func setupPTTChannel() {
        // HUMAN: Provide your APNs token via PTChannelManager when available.
        // PTChannelManager integration is skipped here because it requires a registered
        // push-to-talk channel with Apple's servers to wake the app in background.
        // For foreground PTT the startTalking/stopTalking methods above are sufficient.
    }
}
