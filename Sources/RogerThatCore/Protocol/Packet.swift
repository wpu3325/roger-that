import Foundation

/// Cleartext header flags.
public struct PacketFlags: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Body is AEAD-encrypted.
    public static let bodyEncrypted = PacketFlags(rawValue: 1 << 0)
}

/// Fully-decoded packet (header + body already separated).
public struct Packet: Sendable {
    public var version: UInt8
    public var type: MessageType
    public var flags: PacketFlags
    /// Hops remaining; used only for TEXT flooding.
    public var ttl: UInt8
    /// Truncated hash of the channel id (cleartext scoping key).
    public var channelIDHash: UInt32
    public var senderID: UInt32
    public var messageID: UInt64
    /// Raw body bytes (may be cleartext or ciphertext depending on flags).
    public var body: Data

    public init(
        version: UInt8 = 1,
        type: MessageType,
        flags: PacketFlags = [],
        ttl: UInt8 = 0,
        channelIDHash: UInt32,
        senderID: UInt32,
        messageID: UInt64,
        body: Data
    ) {
        self.version = version
        self.type = type
        self.flags = flags
        self.ttl = ttl
        self.channelIDHash = channelIDHash
        self.senderID = senderID
        self.messageID = messageID
        self.body = body
    }
}

// MARK: - Equatable

extension Packet: Equatable {
    public static func == (lhs: Packet, rhs: Packet) -> Bool {
        lhs.version == rhs.version &&
        lhs.type == rhs.type &&
        lhs.flags == rhs.flags &&
        lhs.ttl == rhs.ttl &&
        lhs.channelIDHash == rhs.channelIDHash &&
        lhs.senderID == rhs.senderID &&
        lhs.messageID == rhs.messageID &&
        lhs.body == rhs.body
    }
}
