import Foundation

/// Delivered message payload after decoding and (optionally) decryption.
public struct ReceivedMessage: Sendable {
    public let packet: Packet
    public let plaintext: Data
}

/// Callback invoked when a text message is delivered to this node.
public typealias MessageHandler = @Sendable (ReceivedMessage) -> Void

/// Flood-routing engine for TEXT packets.
///
/// - Floods TEXT across all Link neighbours with split-horizon and TTL decay.
/// - Deduplicates via SeenCache.
/// - VOICE_FRAME / TALK_* are not routed; they go directly via the voice link.
public final class FloodRouter: @unchecked Sendable {

    public static let defaultTTL: UInt8 = 8
    /// Jitter range for rebroadcast delay (seconds).
    private static let jitterRange: ClosedRange<Double> = 0.02 ... 0.10

    private let link: any Link
    private let seenCache: SeenCache
    private let channelIDHash: UInt32
    private let senderID: UInt32
    private let crypto: ChannelCrypto?
    private var onMessage: MessageHandler?
    private let lock = NSLock()

    /// When true, jitter is skipped (useful for deterministic unit tests).
    public var synchronousDelivery: Bool = false

    public init(
        link: any Link,
        channelIDHash: UInt32,
        senderID: UInt32,
        crypto: ChannelCrypto? = nil,
        seenCache: SeenCache = SeenCache()
    ) {
        self.link = link
        self.channelIDHash = channelIDHash
        self.senderID = senderID
        self.crypto = crypto
        self.seenCache = seenCache

        link.setHandlers(
            onReceive: { [weak self] data, peer in self?.handleReceive(data: data, from: peer) },
            onPeerEvent: { _, _ in }
        )
    }

    public func setMessageHandler(_ handler: @escaping MessageHandler) {
        lock.withLock { onMessage = handler }
    }

    // MARK: - Originate

    /// Encode and flood a text message originating from this node.
    public func send(text: Data) {
        let messageID = UInt64.random(in: .min ... .max)
        var body = text

        var flags: PacketFlags = []
        if let crypto {
            if let encrypted = try? crypto.encrypt(body) {
                body = encrypted
                flags = .bodyEncrypted
            }
        }

        let packet = Packet(
            type: .text,
            flags: flags,
            ttl: Self.defaultTTL,
            channelIDHash: channelIDHash,
            senderID: senderID,
            messageID: messageID,
            body: body
        )

        seenCache.insert(senderID: senderID, messageID: messageID)

        if let encoded = try? PacketCodec.encode(packet) {
            link.broadcast(encoded)
        }
    }

    // MARK: - Receive

    private func handleReceive(data: Data, from peer: PeerHandle) {
        guard let packet = try? PacketCodec.decode(data) else { return }

        // Only process TEXT in the flood router.
        guard packet.type == .text else { return }

        // Drop cross-channel packets.
        guard packet.channelIDHash == channelIDHash else { return }

        // Dedup.
        guard seenCache.insert(senderID: packet.senderID, messageID: packet.messageID) else { return }

        // Decrypt body if needed.
        let plaintext: Data
        if packet.flags.contains(.bodyEncrypted), let crypto {
            guard let decrypted = try? crypto.decrypt(packet.body) else { return }
            plaintext = decrypted
        } else {
            plaintext = packet.body
        }

        // Deliver to this node.
        let handler = lock.withLock { onMessage }
        handler?(ReceivedMessage(packet: packet, plaintext: plaintext))

        // Relay with decremented TTL, excluding arrival link (split-horizon).
        if packet.ttl > 0 {
            var relay = packet
            relay.ttl -= 1
            if let encoded = try? PacketCodec.encode(relay) {
                if synchronousDelivery {
                    rebroadcast(encoded, excluding: peer)
                } else {
                    let jitter = Double.random(in: Self.jitterRange)
                    DispatchQueue.global().asyncAfter(deadline: .now() + jitter) { [weak self] in
                        self?.rebroadcast(encoded, excluding: peer)
                    }
                }
            }
        }
    }

    private func rebroadcast(_ data: Data, excluding exclude: PeerHandle) {
        for peer in link.peers where peer != exclude {
            link.send(data, to: peer)
        }
    }
}
