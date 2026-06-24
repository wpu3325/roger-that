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

        audioEngine.stopCapture()
        sendTalkEnd()
        // The voice link stays up for the whole channel session (managed by AppState),
        // so peers remain connected and can hear the next person who talks.
    }

    // MARK: - Init

    init(localID: UInt32, voiceLink: MultipeerVoiceLink, audioEngine: AudioEngineIO) {
        self.localID = localID
        self.voiceLink = voiceLink
        self.audioEngine = audioEngine
        super.init()
        setupPTTChannel()
    }

    // MARK: - Private

    private let localID: UInt32
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
        let pkt = Packet(type: .talkStart, channelIDHash: 0,
                         senderID: localID, messageID: UInt64.random(in: .min ... .max), body: body)
        if let data = try? PacketCodec.encode(pkt) { voiceLink.broadcast(data) }
    }

    private func sendTalkEnd() {
        var idBytes = talkSessionID.bigEndian
        let body = Data(bytes: &idBytes, count: 4)
        let pkt = Packet(type: .talkEnd, channelIDHash: 0,
                         senderID: localID, messageID: UInt64.random(in: .min ... .max), body: body)
        if let data = try? PacketCodec.encode(pkt) { voiceLink.broadcast(data) }
    }

    private func sendVoiceFrame(_ frame: Data) {
        var sessionIDBytes = talkSessionID.bigEndian
        var seqBytes = voiceSeq.bigEndian
        voiceSeq += 1
        var body = Data(bytes: &sessionIDBytes, count: 4)
        body.append(Data(bytes: &seqBytes, count: 4))
        body.append(frame)
        let pkt = Packet(type: .voiceFrame, channelIDHash: 0,
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
