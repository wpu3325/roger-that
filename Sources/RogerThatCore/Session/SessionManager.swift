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
    }

    // MARK: - Public API

    public func start() {
        schedulePresenceBeacon()
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

    public var activeMembers: [Member] { roster.activeMembersSnapshot() }
    public var floorState: FloorState { floor.state }

    // MARK: - Private

    private func handleMessage(_ msg: ReceivedMessage) {
        switch msg.packet.type {
        case .presence:
            if let name = String(data: msg.plaintext, encoding: .utf8) {
                roster.upsert(id: msg.packet.senderID, displayName: name)
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
        timer.schedule(deadline: .now(), repeating: 15)
        timer.setEventHandler { [weak self] in self?.broadcastPresence() }
        timer.resume()
        presenceTimer = timer
    }

    private func broadcastPresence() {
        guard let data = displayName.data(using: .utf8) else { return }
        router.send(text: data)
    }
}
