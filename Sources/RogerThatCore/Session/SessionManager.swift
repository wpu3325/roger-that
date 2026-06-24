import Foundation

/// Central coordinator for a joined channel session.
///
/// Ties together the flood router (text + presence), roster, and PTT floor.
/// Voice frame delivery is handled directly by the app layer.
public final class SessionManager: @unchecked Sendable {

    public let channel: Channel
    public let localID: UInt32
    public let displayName: String

    private let router: FloodRouter
    private let roster: Roster
    private let floor: PTTFloor
    private let crypto: ChannelCrypto

    private var onMessageReceived: (@Sendable (ReceivedMessage) -> Void)?
    private var onRosterChanged: (@Sendable () -> Void)?
    private let lock = NSLock()

    /// Presence beacon interval.
    private var presenceTimer: DispatchSourceTimer?

    public init(
        channel: Channel,
        localID: UInt32,
        displayName: String,
        link: any Link
    ) {
        self.channel = channel
        self.localID = localID
        self.displayName = displayName
        self.crypto = ChannelCrypto(key: channel.key)
        self.roster = Roster()
        self.floor = PTTFloor()
        self.router = FloodRouter(
            link: link,
            channelIDHash: channel.channelIDHash,
            senderID: localID,
            crypto: crypto
        )

        router.setMessageHandler { [weak self] msg in
            self?.handleMessage(msg)
        }

        // When a transport peer connects, announce ourselves right away so we appear
        // in their roster immediately instead of after the next 15s beacon.
        router.setPeerConnectedHandler { [weak self] in
            self?.broadcastPresence()
        }
    }

    // MARK: - Public API

    public func start() {
        // Show ourselves in the roster immediately (RosterView marks this "(you)").
        roster.upsert(id: localID, displayName: displayName)
        schedulePresenceBeacon()
    }

    /// Broadcast a presence beacon now (e.g. on pull-to-refresh) so peers re-announce.
    public func announcePresence() {
        broadcastPresence()
    }

    public func stop() {
        presenceTimer?.cancel()
        presenceTimer = nil
    }

    public func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        router.send(text: data)
    }

    public func setMessageHandler(_ handler: @escaping @Sendable (ReceivedMessage) -> Void) {
        lock.withLock { onMessageReceived = handler }
    }

    /// Fired whenever the roster changes (a presence beacon was received).
    public func setRosterChangedHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { onRosterChanged = handler }
    }

    public var activeMembers: [Member] { roster.activeMembersSnapshot() }
    public var floorState: FloorState { floor.state }

    public func setFloorStateHandler(_ handler: @escaping @Sendable (FloorState) -> Void) {
        floor.setStateChangeHandler(handler)
    }

    // MARK: - Private

    private func handleMessage(_ msg: ReceivedMessage) {
        switch msg.packet.type {
        case .presence:
            if let name = String(data: msg.plaintext, encoding: .utf8) {
                roster.upsert(id: msg.packet.senderID, displayName: name)
                let handler = lock.withLock { onRosterChanged }
                handler?()
            }
        case .text:
            let handler = lock.withLock { onMessageReceived }
            handler?(msg)
        case .talkStart:
            let name = roster.activeMembersSnapshot()
                .first(where: { $0.id == msg.packet.senderID })?.displayName ?? "Unknown"
            floor.remoteTalkStart(speakerID: msg.packet.senderID, displayName: name)
        case .talkEnd:
            floor.remoteTalkEnd(speakerID: msg.packet.senderID)
        case .voiceFrame:
            break // handled at the app layer
        }
    }

    private func schedulePresenceBeacon() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now(), repeating: 10)
        timer.setEventHandler { [weak self] in self?.broadcastPresence() }
        timer.resume()
        presenceTimer = timer
    }

    private func broadcastPresence() {
        guard let data = displayName.data(using: .utf8) else { return }
        router.send(presence: data)
    }
}
