import Foundation
import SwiftUI
import RogerThatCore

/// Observable state for the entire app. Lives on the main actor.
///
/// Multi-channel model: you can be a member of several channels at once. One shared BLE
/// transport (via `LinkHub`) feeds one `SessionManager` per joined channel, so background
/// channels keep collecting text/presence (and unread counts) even while another is open.
/// Exactly one channel is *active* at a time (you can only talk/look at one) — its voice
/// link + audio engine are the only ones running, and its data is mirrored into the
/// `channel`/`members`/`messages`/`floorState`/`voiceLevel` properties the in-channel UI
/// already reads, so those views didn't need to change.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Active-channel mirror (read by the in-channel UI)

    @Published var session: SessionManager?
    @Published var channel: Channel?
    @Published var members: [Member] = []
    @Published var messages: [ChatMessage] = []
    @Published var floorState: FloorState = .idle
    /// Normalized 0...1 audio level of whoever currently holds the floor (drives waveform).
    @Published var voiceLevel: Float = 0

    // MARK: - Multi-channel state

    /// Joined channels, in list order (drives the channel list).
    @Published var joinedChannels: [ChannelMetadata] = []
    /// The currently open channel, or nil when browsing the channel list.
    @Published var activeChannelID: String?
    /// Unread message counts for channels that aren't currently open.
    @Published var unreadByChannel: [String: Int] = [:]

    private(set) var pttController: PushToTalkController?

    // Per-channel background state, keyed by channelID.
    private var sessions: [String: SessionManager] = [:]
    private var ports: [String: any RogerThatCore.Link] = [:]
    private var channelsByID: [String: Channel] = [:]
    private var messagesByChannel: [String: [ChatMessage]] = [:]
    private var membersByChannel: [String: [Member]] = [:]
    /// Per-channel member IDs already announced as "joined" (cumulative; avoids BLE-flap spam).
    private var knownMembersByChannel: [String: Set<UInt32>] = [:]

    // MARK: - Shared transport

    /// One channel-agnostic BLE link shared by every channel; the hub fans it out per channel.
    private let bleLink: BLEMeshLink
    private let hub: LinkHub
    private var transportStarted = false

    // MARK: - Active-channel voice (only one runs at a time)

    private var voiceLink: MultipeerVoiceLink?
    private var audioEngine: AudioEngineIO?
    /// Opens sealed voice frames arriving over the Multipeer link (channel-key AEAD).
    private var voiceCrypto: ChannelCrypto?
    /// Reorders incoming voice frames, drops dups, and flags losses for concealment.
    private let voiceJitter = VoiceJitterBuffer()
    /// Clears the remote-talking banner if voice frames stop arriving.
    private var voiceWatchdog: Task<Void, Never>?

    private let store = ChannelStore()
    private let messageStore = MessageStore()
    private var rosterTimer: DispatchSourceTimer?

    /// Whether the app is in the foreground (drives notification suppression — a banner is
    /// posted only for messages that aren't already on screen). Updated from scenePhase.
    var isForeground = true

    /// False while a peer holds the floor — PTT is half-duplex, so we block local TX to
    /// avoid two people transmitting over each other and garbling the audio.
    var canStartTalking: Bool {
        if case .talkingRemote = floorState { return false }
        return true
    }

    /// Metadata for the channel that's currently open.
    var activeMetadata: ChannelMetadata? {
        joinedChannels.first { $0.channelID == activeChannelID }
    }

    /// How many members a channel currently sees (for the channel list).
    func memberCount(for channelID: String) -> Int {
        membersByChannel[channelID]?.count ?? 0
    }

    /// This device's persistent random ID.
    let localID: UInt32 = {
        let key = "rogerthat.deviceID"
        if let stored = UserDefaults.standard.object(forKey: key) as? UInt32 { return stored }
        let id = UInt32.random(in: .min ... .max)
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    /// Current call sign (shared across all channels).
    private var displayName: String {
        UserDefaults.standard.string(forKey: "rogerthat.callSign") ?? "Me"
    }

    private var didBootstrap = false

    init() {
        let ble = BLEMeshLink(channelIDHash: 0)
        bleLink = ble
        hub = LinkHub(base: ble)
        PTTIntentBridge.shared.appState = self
        NotificationManager.shared.appState = self
        // Populate the list from metadata only (cheap UserDefaults read, no Keychain/BLE)
        // so the root view routes to the channel list on the first frame — no first-run
        // flash. The heavy work (Keychain keys + starting CoreBluetooth + sessions) is
        // deferred to bootstrap(), which is what removes the launch lag.
        joinedChannels = store.metadataList()
    }

    /// Deferred startup: load saved channels and begin background collection. Idempotent.
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if !joinedChannels.isEmpty { NotificationManager.shared.requestAuthorizationIfNeeded() }
        loadPersistedChannels()
    }

    // MARK: - Channel membership

    /// Join (or create) a channel: persist it, start collecting in the background, and open it.
    /// `name`/`kind` describe how it's shared; defaults suit a random-key QR/code channel.
    func join(channel: Channel, displayName: String,
              name: String? = nil, kind: ChannelMetadata.Kind = .random) {
        let id = channel.channelID
        // Reuse the existing name if we're rejoining a channel we already know.
        let existing = joinedChannels.first { $0.channelID == id }
        let meta = ChannelMetadata(
            channelID: id,
            name: name ?? existing?.name ?? Self.defaultName(for: channel),
            kind: kind,
            joinedAt: existing?.joinedAt ?? Date(),
            isArchived: false
        )
        if let idx = joinedChannels.firstIndex(where: { $0.channelID == id }) {
            joinedChannels[idx] = meta            // un-archive if it was parked
        }
        if sessions[id] == nil {
            store.add(meta, channel: channel)
            startSession(for: channel, meta: meta)
        }
        NotificationManager.shared.requestAuthorizationIfNeeded()
        openChannel(id)
    }

    /// Open a channel from the list. If it was archived ("left"), rejoin it first — restart
    /// its session — so its history is live again; otherwise just make it active.
    func openChannel(_ channelID: String) {
        if let idx = joinedChannels.firstIndex(where: { $0.channelID == channelID }),
           joinedChannels[idx].isArchived {
            joinedChannels[idx].isArchived = false
            let meta = joinedChannels[idx]
            if let channel = channelsByID[channelID] {
                if sessions[channelID] == nil { startSession(for: channel, meta: meta) }
                store.add(meta, channel: channel)   // persist the un-archive
            }
        }
        setActive(channelID)
    }

    /// "Leave" a channel: stop its session but keep it (archived) along with its key and
    /// message history. It moves to the Archived section; reopening rejoins it.
    func archive(_ channelID: String) {
        guard let idx = joinedChannels.firstIndex(where: { $0.channelID == channelID }) else { return }
        if activeChannelID == channelID { setActive(nil) }
        sessions[channelID]?.stop()
        if let port = ports[channelID] { hub.removePort(port) }
        sessions[channelID] = nil
        ports[channelID] = nil
        membersByChannel[channelID] = []                 // roster is runtime-only
        knownMembersByChannel[channelID] = [localID]
        unreadByChannel[channelID] = nil
        joinedChannels[idx].isArchived = true
        if let channel = channelsByID[channelID] {
            store.add(joinedChannels[idx], channel: channel)   // persist isArchived
        }
        // channelsByID + messagesByChannel (and the on-disk history) are kept intact.
        if sessions.isEmpty { stopTransport() }
    }

    /// "Delete" a channel entirely: scrub its key, metadata, and message history. The
    /// storage teardown runs off-main so the list animates instantly (no deletion lag).
    func delete(_ channelID: String) {
        if activeChannelID == channelID { setActive(nil) }
        sessions[channelID]?.stop()
        if let port = ports[channelID] { hub.removePort(port) }
        sessions[channelID] = nil
        ports[channelID] = nil
        channelsByID[channelID] = nil
        messagesByChannel[channelID] = nil
        membersByChannel[channelID] = nil
        knownMembersByChannel[channelID] = nil
        unreadByChannel[channelID] = nil
        joinedChannels.removeAll { $0.channelID == channelID }
        let store = self.store
        let messageStore = self.messageStore
        Task.detached(priority: .utility) {
            store.remove(channelID)        // Keychain + UserDefaults, off the main thread
            messageStore.delete(channelID) // history file
        }
        if sessions.isEmpty { stopTransport() }
    }

    /// Rename a channel (persisted). No effect on its key or membership.
    func rename(_ channelID: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = joinedChannels.firstIndex(where: { $0.channelID == channelID }) else { return }
        joinedChannels[idx].name = trimmed
        if let channel = channelsByID[channelID] {
            store.add(joinedChannels[idx], channel: channel)
        }
    }

    /// "Leave" the channel that's currently open (archives it).
    func leaveActiveChannel() {
        if let id = activeChannelID { archive(id) }
    }

    /// Open a channel (mirror its state + bring up voice), or nil to return to the list.
    func setActive(_ channelID: String?) {
        stopActiveVoice()
        voiceJitter.reset()
        floorState = .idle
        voiceLevel = 0

        activeChannelID = channelID
        guard let channelID, let channel = channelsByID[channelID] else {
            session = nil
            self.channel = nil
            members = []
            messages = []
            return
        }

        self.channel = channel
        session = sessions[channelID]
        members = membersByChannel[channelID] ?? []
        messages = messagesByChannel[channelID] ?? []
        unreadByChannel[channelID] = 0
        startActiveVoice(channel: channel)
    }

    // MARK: - Session setup (background, per channel)

    private func startSession(for channel: Channel, meta: ChannelMetadata) {
        let id = channel.channelID
        channelsByID[id] = channel
        messagesByChannel[id] = messagesByChannel[id] ?? messageStore.load(id)
        membersByChannel[id] = membersByChannel[id] ?? []
        knownMembersByChannel[id] = [localID]   // seed self so we never post "you joined"

        let port = hub.makePort()
        ports[id] = port
        let mgr = SessionManager(channel: channel, localID: localID, displayName: displayName, link: port)

        mgr.setMessageHandler { [weak self] msg in
            guard msg.packet.type == .text,
                  let text = String(data: msg.plaintext, encoding: .utf8) else { return }
            Task { @MainActor in self?.handleIncomingText(text, senderID: msg.packet.senderID, channelID: id) }
        }
        mgr.setRosterChangedHandler { [weak self, weak mgr] in
            Task { @MainActor in
                guard let self, let mgr else { return }
                self.syncRoster(mgr.activeMembers, channelID: id)
            }
        }

        sessions[id] = mgr
        if !joinedChannels.contains(where: { $0.channelID == id }) {
            joinedChannels.append(meta)
        }

        ensureTransportStarted()
        mgr.start()
    }

    private func ensureTransportStarted() {
        guard !transportStarted else { return }
        transportStarted = true
        hub.start()
        scheduleRosterRefresh()
    }

    private func stopTransport() {
        rosterTimer?.cancel()
        rosterTimer = nil
        hub.stop()
        transportStarted = false
    }

    // MARK: - Active-channel voice

    private func startActiveVoice(channel: Channel) {
        let crypto = ChannelCrypto(key: channel.key)
        voiceCrypto = crypto

        let voice = MultipeerVoiceLink(channelIDHash: channel.channelIDHash, localID: localID)
        voice.setHandlers(
            onReceive: { [weak self] data, _ in Task { @MainActor in self?.handleVoicePacket(data) } },
            onPeerEvent: { _, _ in }
        )

        let engine = AudioEngineIO()
        let ptt = PushToTalkController(
            localID: localID,
            channelIDHash: channel.channelIDHash,
            crypto: crypto,
            voiceLink: voice,
            audioEngine: engine
        )

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

        voiceLink = voice
        audioEngine = engine
        pttController = ptt

        // Keep the voice link + audio engine up the whole time the channel is open, so we
        // hear peers the instant they talk (not only while we're transmitting).
        voice.start()
        engine.startSession()
    }

    private func stopActiveVoice() {
        pttController?.stopTalking()
        voiceLink?.stop()
        audioEngine?.stopSession()
        voiceWatchdog?.cancel()
        voiceWatchdog = nil
        pttController = nil
        voiceLink = nil
        audioEngine = nil
        voiceCrypto = nil
    }

    // MARK: - Incoming text + roster (per channel)

    private func handleIncomingText(_ text: String, senderID: UInt32, channelID: String) {
        let name = membersByChannel[channelID]?.first { $0.id == senderID }?.displayName ?? "Peer"
        appendMessage(ChatMessage(senderName: name, text: text, timestamp: Date(), isLocal: false),
                      to: channelID)

        // On screen (this channel open, app foreground) → just a haptic. Otherwise (locked,
        // backgrounded, or a different page) → a banner with the message text, and bump the
        // unread badge when it's a different channel than the one we're looking at.
        let onScreen = isForeground && channelID == activeChannelID
        if onScreen {
            Haptics.messageReceived()
        } else {
            if channelID != activeChannelID { unreadByChannel[channelID, default: 0] += 1 }
            let channelName = joinedChannels.first { $0.channelID == channelID }?.name ?? "Roger That"
            NotificationManager.shared.postMessage(channelName: channelName, sender: name,
                                                   body: text, channelID: channelID)
        }
    }

    /// Update a channel's roster and post a centered "X joined" notice for new members.
    private func syncRoster(_ snapshot: [Member], channelID: String) {
        var known = knownMembersByChannel[channelID] ?? [localID]
        for member in snapshot where !known.contains(member.id) {
            known.insert(member.id)
            appendMessage(.system("\(member.displayName) joined"), to: channelID)
        }
        knownMembersByChannel[channelID] = known
        membersByChannel[channelID] = snapshot
        if channelID == activeChannelID { members = snapshot }
    }

    private func appendMessage(_ message: ChatMessage, to channelID: String) {
        messagesByChannel[channelID, default: []].append(message)
        messageStore.save(messagesByChannel[channelID] ?? [], for: channelID)
        if channelID == activeChannelID { messages = messagesByChannel[channelID] ?? [] }
    }

    func sendText(_ text: String) {
        guard let id = activeChannelID, let session = sessions[id] else { return }
        session.sendText(text)
        appendMessage(ChatMessage(senderName: "You", text: text, timestamp: Date(), isLocal: true), to: id)
    }

    /// Pull-to-refresh: re-announce presence on the active channel, then snapshot its roster.
    func refreshRoster() async {
        guard let id = activeChannelID else { return }
        sessions[id]?.announcePresence()
        try? await Task.sleep(nanoseconds: 700_000_000)
        if let mgr = sessions[id] { syncRoster(mgr.activeMembers, channelID: id) }
    }

    // MARK: - Voice receive (active channel)

    private func handleVoicePacket(_ data: Data) {
        guard let packet = try? PacketCodec.decode(data) else { return }
        // Drop cross-channel voice/talk: even if a stray Multipeer session forms across
        // channels, packets stamped with another channel's hash are ignored here.
        guard packet.channelIDHash == channel?.channelIDHash else { return }

        switch packet.type {
        case .voiceFrame:
            // Body is sealed with the channel key; open returns [sessionID][seq][frame] or
            // nil (wrong channel / tampered), in which case we just drop the frame.
            guard let crypto = voiceCrypto,
                  let (sessionID, seq, payload) = VoiceBody.open(packet.body, crypto: crypto) else { return }
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

    /// Show the remote-talking banner and (re)arm a watchdog. Driven by voice-frame flow
    /// plus this timeout, so a dropped (unreliable) TALK_START/END can't leave it stuck.
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

    // MARK: - Startup / timers

    private func loadPersistedChannels() {
        // Read Keychain keys + on-disk history off the main thread, then install on main.
        // This is what removes the launch stall (the reads no longer block the first frames).
        let store = self.store
        let messageStore = self.messageStore
        Task.detached(priority: .userInitiated) {
            let entries = store.load()
            let histories: [String: [ChatMessage]] = entries.reduce(into: [:]) { acc, entry in
                acc[entry.channel.channelID] = messageStore.load(entry.channel.channelID)
            }
            await MainActor.run { self.installPersistedChannels(entries, histories: histories) }
        }
        // Start on the channel list (no channel auto-opened).
    }

    private func installPersistedChannels(_ entries: [(meta: ChannelMetadata, channel: Channel)],
                                          histories: [String: [ChatMessage]]) {
        for entry in entries {
            let id = entry.channel.channelID
            channelsByID[id] = entry.channel
            messagesByChannel[id] = histories[id] ?? []
            if entry.meta.isArchived {
                // Parked: no live session. History is available; opening it rejoins.
                knownMembersByChannel[id] = [localID]
                membersByChannel[id] = []
            } else {
                startSession(for: entry.channel, meta: entry.meta)
            }
        }
    }

    /// Periodically re-snapshot every channel's roster (belt-and-braces over the
    /// event-driven `setRosterChangedHandler`).
    private func scheduleRosterRefresh() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Belt-and-braces over the event-driven roster handler; 12s keeps it cheap (battery).
        timer.schedule(deadline: .now() + 12, repeating: 12)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                for (id, mgr) in self.sessions {
                    self.syncRoster(mgr.activeMembers, channelID: id)
                }
            }
        }
        timer.resume()
        rosterTimer = timer
    }

    private static func defaultName(for channel: Channel) -> String {
        let hex = String(format: "%08X", channel.channelIDHash)
        return "Channel \(hex.prefix(4))·\(hex.suffix(4))"
    }
}
