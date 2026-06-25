import Foundation
import SwiftUI
import RogerThatCore

/// Observable state for the entire app. Lives on the main actor.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var session: SessionManager?
    @Published var channel: Channel?
    @Published var members: [Member] = []
    @Published var messages: [ChatMessage] = []
    @Published var floorState: FloorState = .idle
    /// Normalized 0...1 audio level of whoever currently holds the floor (drives waveform).
    @Published var voiceLevel: Float = 0

    // MARK: - Dependencies (set up on join)

    private(set) var pttController: PushToTalkController?
    private var bleLink: BLEMeshLink?
    private var voiceLink: MultipeerVoiceLink?
    private var audioEngine: AudioEngineIO?

    /// Member IDs we've already announced as "joined" (cumulative for the session, so
    /// flaky BLE drop/return doesn't spam the chat with repeated join notices).
    private var knownMemberIDs: Set<UInt32> = []

    /// Clears the remote-talking banner if voice frames stop arriving.
    private var voiceWatchdog: Task<Void, Never>?

    /// Reorders incoming voice frames, drops dups, and flags losses for concealment.
    private let voiceJitter = VoiceJitterBuffer()

    /// False while a peer holds the floor — PTT is half-duplex, so we block local TX to
    /// avoid two people transmitting over each other and garbling the audio.
    var canStartTalking: Bool {
        if case .talkingRemote = floorState { return false }
        return true
    }

    /// This device's persistent random ID.
    let localID: UInt32 = {
        let key = "rogerthat.deviceID"
        if let stored = UserDefaults.standard.object(forKey: key) as? UInt32 { return stored }
        let id = UInt32.random(in: .min ... .max)
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    // MARK: - Channel lifecycle

    init() {
        PTTIntentBridge.shared.appState = self
    }

    func join(channel: Channel, displayName: String) {
        // Seed with self so we never post a "you joined" notice.
        knownMemberIDs = [localID]

        let ble = BLEMeshLink(channelIDHash: channel.channelIDHash)
        let voice = MultipeerVoiceLink(channelIDHash: channel.channelIDHash, localID: localID)
        let mgr = SessionManager(
            channel: channel,
            localID: localID,
            displayName: displayName,
            link: ble
        )

        mgr.setMessageHandler { [weak self] msg in
            guard let self else { return }
            Task { @MainActor in
                let name = self.members.first(where: { $0.id == msg.packet.senderID })?.displayName
                    ?? "Peer"
                if msg.packet.type == .text,
                   let text = String(data: msg.plaintext, encoding: .utf8) {
                    self.messages.append(ChatMessage(
                        senderName: name,
                        text: text,
                        timestamp: Date(),
                        isLocal: false
                    ))
                    Haptics.messageReceived()
                }
            }
        }

        // Receive incoming voice/talk packets over the Multipeer voice link.
        voice.setHandlers(
            onReceive: { [weak self] data, _ in
                Task { @MainActor in self?.handleVoicePacket(data) }
            },
            onPeerEvent: { _, _ in }
        )

        let engine = AudioEngineIO()
        let ptt = PushToTalkController(
            localID: localID,
            voiceLink: voice,
            audioEngine: engine
        )

        // Drive the waveform from real audio amplitude.
        engine.onInputLevel = { [weak self] level in
            Task { @MainActor in
                guard let self, case .talkingLocal = self.floorState else { return }
                self.voiceLevel = level
            }
        }
        engine.onOutputLevel = { [weak self] level in
            Task { @MainActor in
                guard let self, case .talkingRemote = self.floorState else { return }
                self.voiceLevel = level
            }
        }

        ptt.onFloorStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.floorState = state
                if case .idle = state { self.voiceLevel = 0 }
            }
        }

        // Roster updates immediately when a presence beacon arrives (not just on the 5s poll).
        mgr.setRosterChangedHandler { [weak self, weak mgr] in
            Task { @MainActor in
                guard let self, let mgr else { return }
                self.syncRoster(mgr.activeMembers)
            }
        }

        // Remote floor state (TALK_START/END from peers) updates immediately.
        mgr.setFloorStateHandler { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                // Don't overwrite local talking state with remote idle.
                if case .talkingLocal = self.floorState { return }
                self.floorState = state
            }
        }

        self.bleLink = ble
        self.voiceLink = voice
        self.audioEngine = engine
        self.session = mgr
        self.channel = channel
        self.pttController = ptt

        ble.start()
        mgr.start()
        // Keep the voice link + audio engine up for the whole session so we can hear
        // peers the instant they talk (not only while we're transmitting).
        voice.start()
        engine.startSession()

        // Poll presence/roster on a timer.
        scheduleRosterRefresh(mgr: mgr)
    }

    func leaveChannel() {
        session?.stop()
        bleLink?.stop()
        pttController?.stopTalking()
        voiceLink?.stop()
        audioEngine?.stopSession()
        audioEngine = nil
        voiceJitter.reset()
        voiceWatchdog?.cancel()
        voiceWatchdog = nil
        voiceLevel = 0
        session = nil
        channel = nil
        members = []
        messages = []
        knownMemberIDs = []
        floorState = .idle
        pttController = nil
        bleLink = nil
        voiceLink = nil
        rosterTimer?.cancel()
        rosterTimer = nil
    }

    /// Pull-to-refresh: re-announce our presence, give peers a moment to reply,
    /// then snapshot the latest roster.
    func refreshRoster() async {
        session?.announcePresence()
        try? await Task.sleep(nanoseconds: 700_000_000)
        members = session?.activeMembers ?? []
    }

    // MARK: - Voice receive

    /// Decode a packet arriving over the Multipeer voice link: play voice frames and
    /// reflect remote talk state in the floor banner.
    private func handleVoicePacket(_ data: Data) {
        guard let packet = try? PacketCodec.decode(data) else { return }
        switch packet.type {
        case .voiceFrame:
            // body = [sessionID u32 BE][seq u32 BE][encoded frame]
            let body = Data(packet.body)
            guard body.count >= 8 else { return }
            let sessionID = Self.bigEndianUInt32(body[0..<4])
            let seq = Self.bigEndianUInt32(body[4..<8])
            let payload = Data(body[8...])
            // Run through the jitter buffer: it returns frames in order, plus concealment
            // for any it judges lost, so playback stays crisp under reordering/loss.
            for output in voiceJitter.enqueue(VoiceFrame(sessionID: sessionID, seq: seq, payload: payload)) {
                switch output {
                case .play(let frame): audioEngine?.playEncoded(frame)
                case .conceal:         audioEngine?.playConcealment()
                }
            }
            showRemoteTalking(senderID: packet.senderID)
        case .talkStart:
            showRemoteTalking(senderID: packet.senderID)
        case .talkEnd:
            voiceJitter.reset()
            endRemoteTalking(senderID: packet.senderID)
        default:
            break
        }
    }

    /// Read a big-endian UInt32 from a 4-byte slice (slice indices may not start at 0).
    private static func bigEndianUInt32(_ bytes: Data) -> UInt32 {
        bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    /// Show the remote-talking banner and (re)arm a watchdog. The banner is driven by
    /// the actual voice-frame flow plus this watchdog, so a dropped TALK_START/END (both
    /// sent unreliably) can't leave the indicator missing or stuck — it stays consistent.
    private func showRemoteTalking(senderID: UInt32) {
        if case .talkingLocal = floorState { return }   // never override our own transmission
        let name = members.first { $0.id == senderID }?.displayName ?? "Someone"
        floorState = .talkingRemote(speakerID: senderID, displayName: name)

        voiceWatchdog?.cancel()
        voiceWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .talkingRemote = self.floorState {
                self.floorState = .idle
                self.voiceLevel = 0
            }
        }
    }

    private func endRemoteTalking(senderID: UInt32) {
        if case .talkingRemote(let id, _) = floorState, id == senderID {
            voiceWatchdog?.cancel()
            floorState = .idle
            voiceLevel = 0
        }
    }

    func sendText(_ text: String) {
        guard let session else { return }
        session.sendText(text)
        messages.append(ChatMessage(
            senderName: "You",
            text: text,
            timestamp: Date(),
            isLocal: true
        ))
    }

    // MARK: - Roster refresh

    /// Update the published roster and post a centered "X joined" notice in chat for
    /// any member we haven't seen before this session.
    private func syncRoster(_ snapshot: [Member]) {
        for member in snapshot where !knownMemberIDs.contains(member.id) {
            knownMemberIDs.insert(member.id)
            messages.append(.system("\(member.displayName) joined"))
        }
        members = snapshot
    }

    private var rosterTimer: DispatchSourceTimer?

    private func scheduleRosterRefresh(mgr: SessionManager) {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 5)
        t.setEventHandler { [weak self, weak mgr] in
            guard let self, let mgr else { return }
            Task { @MainActor in
                self.syncRoster(mgr.activeMembers)
                // floorState is managed by ptt.onFloorStateChange and mgr.setFloorStateHandler;
                // do NOT overwrite it here or local PTT state gets clobbered every 5 seconds.
            }
        }
        t.resume()
        rosterTimer = t
    }
}
