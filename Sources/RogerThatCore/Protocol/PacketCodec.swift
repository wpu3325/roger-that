import Foundation

/// Errors from packet encoding/decoding.
public enum PacketCodecError: Error, Sendable, Equatable {
    case bufferTooShort
    case unknownVersion(UInt8)
    case unknownMessageType(UInt8)
    case payloadLengthMismatch
}

/// Stateless encoder/decoder for the Roger That wire format.
///
/// Wire layout (big-endian):
///   version     u8   (1 byte)
///   type        u8   (1 byte)
///   flags       u8   (1 byte)
///   ttl         u8   (1 byte)
///   channelIDHash u32 (4 bytes)
///   senderID    u32  (4 bytes)
///   messageID   u64  (8 bytes)
///   payloadLen  u16  (2 bytes)
///   body        [payloadLen bytes]
///
/// Total header: 22 bytes.
public enum PacketCodec {

    static let headerSize = 22

    // MARK: - Encode

    public static func encode(_ packet: Packet) throws -> Data {
        guard packet.body.count <= UInt16.max else {
            throw PacketCodecError.payloadLengthMismatch
        }
        var data = Data(capacity: headerSize + packet.body.count)
        data.appendBigEndian(packet.version)
        data.appendBigEndian(packet.type.rawValue)
        data.appendBigEndian(packet.flags.rawValue)
        data.appendBigEndian(packet.ttl)
        data.appendBigEndian(packet.channelIDHash)
        data.appendBigEndian(packet.senderID)
        data.appendBigEndian(packet.messageID)
        data.appendBigEndian(UInt16(packet.body.count))
        data.append(packet.body)
        return data
    }

    // MARK: - Decode

    public static func decode(_ data: Data) throws -> Packet {
        guard data.count >= headerSize else {
            throw PacketCodecError.bufferTooShort
        }
        var offset = data.startIndex

        let version: UInt8 = try data.readBigEndian(at: &offset)
        guard version == 1 else { throw PacketCodecError.unknownVersion(version) }

        let typeRaw: UInt8 = try data.readBigEndian(at: &offset)
        guard let type = MessageType(rawValue: typeRaw) else {
            throw PacketCodecError.unknownMessageType(typeRaw)
        }

        let flagsRaw: UInt8 = try data.readBigEndian(at: &offset)
        let flags = PacketFlags(rawValue: flagsRaw)

        let ttl: UInt8 = try data.readBigEndian(at: &offset)
        let channelIDHash: UInt32 = try data.readBigEndian(at: &offset)
        let senderID: UInt32 = try data.readBigEndian(at: &offset)
        let messageID: UInt64 = try data.readBigEndian(at: &offset)
        let payloadLen: UInt16 = try data.readBigEndian(at: &offset)

        let remaining = data.count - (offset - data.startIndex)
        guard remaining >= payloadLen else {
            throw PacketCodecError.payloadLengthMismatch
        }

        let body = data[offset ..< offset + Int(payloadLen)]

        return Packet(
            version: version,
            type: type,
            flags: flags,
            ttl: ttl,
            channelIDHash: channelIDHash,
            senderID: senderID,
            messageID: messageID,
            body: Data(body)
        )
    }
}

// MARK: - Data helpers (big-endian)

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { self.append(contentsOf: $0) }
    }

    func readBigEndian<T: FixedWidthInteger>(at offset: inout Index) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= endIndex else { throw PacketCodecError.bufferTooShort }
        var raw = T()
        _ = Swift.withUnsafeMutableBytes(of: &raw) { ptr in
            self.copyBytes(to: ptr, from: offset ..< offset + size)
        }
        offset += size
        return T(bigEndian: raw)
    }
}
