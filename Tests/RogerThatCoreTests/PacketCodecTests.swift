import Testing
import Foundation
@testable import RogerThatCore

// MARK: - Round-trips for every message type

@Suite("PacketCodec")
struct PacketCodecTests {

    private func make(
        type: MessageType,
        flags: PacketFlags = [],
        ttl: UInt8 = 0,
        channelIDHash: UInt32 = 0xCAFEBABE,
        senderID: UInt32 = 0x11223344,
        messageID: UInt64 = 0x0102030405060708,
        body: Data = Data()
    ) -> Packet {
        Packet(version: 1, type: type, flags: flags, ttl: ttl,
               channelIDHash: channelIDHash, senderID: senderID,
               messageID: messageID, body: body)
    }

    @Test func roundTripPresence() throws {
        let pkt = make(type: .presence, body: Data("Alice".utf8))
        #expect(try PacketCodec.decode(PacketCodec.encode(pkt)) == pkt)
    }

    @Test func roundTripText() throws {
        let pkt = make(type: .text, ttl: 8, body: Data("Hello 🌍".utf8))
        #expect(try PacketCodec.decode(PacketCodec.encode(pkt)) == pkt)
    }

    @Test func roundTripVoiceFrame() throws {
        var body = Data([0,0,0,1, 0,0,0,2])
        body.append(Data(repeating: 0xAB, count: 320))
        let pkt = make(type: .voiceFrame, body: body)
        #expect(try PacketCodec.decode(PacketCodec.encode(pkt)) == pkt)
    }

    @Test func roundTripTalkStart() throws {
        let pkt = make(type: .talkStart, body: Data([0,0,0,7]))
        #expect(try PacketCodec.decode(PacketCodec.encode(pkt)) == pkt)
    }

    @Test func roundTripTalkEnd() throws {
        let pkt = make(type: .talkEnd, body: Data([0,0,0,7]))
        #expect(try PacketCodec.decode(PacketCodec.encode(pkt)) == pkt)
    }

    @Test func encryptedFlagPreserved() throws {
        let pkt = make(type: .text, flags: .bodyEncrypted, body: Data("enc".utf8))
        let decoded = try PacketCodec.decode(PacketCodec.encode(pkt))
        #expect(decoded.flags.contains(.bodyEncrypted))
    }

    @Test func emptyBodyRoundTrip() throws {
        let pkt = make(type: .talkEnd)
        let decoded = try PacketCodec.decode(PacketCodec.encode(pkt))
        #expect(decoded.body.count == 0)
    }

    @Test func headerExactly22Bytes() throws {
        let encoded = try PacketCodec.encode(make(type: .text))
        #expect(encoded.count == 22)
    }

    // MARK: - Big-endian byte ordering

    @Test func bigEndianChannelIDHash() throws {
        let pkt = make(type: .text, channelIDHash: 0xDEADBEEF)
        let encoded = try PacketCodec.encode(pkt)
        #expect(Array(encoded[4..<8]) == [0xDE, 0xAD, 0xBE, 0xEF])
    }

    @Test func bigEndianMessageID() throws {
        let pkt = make(type: .text, messageID: 0x0102030405060708)
        let encoded = try PacketCodec.encode(pkt)
        #expect(Array(encoded[12..<20]) == [0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08])
    }

    // MARK: - Malformed input (no crashes, typed errors)

    @Test func emptyBufferThrows() {
        #expect(throws: PacketCodecError.bufferTooShort) {
            try PacketCodec.decode(Data())
        }
    }

    @Test func truncatedHeaderThrows() {
        #expect(throws: PacketCodecError.bufferTooShort) {
            try PacketCodec.decode(Data(repeating: 0x01, count: 10))
        }
    }

    @Test func unknownVersionThrows() throws {
        var encoded = try PacketCodec.encode(make(type: .text, body: Data("x".utf8)))
        encoded[0] = 99
        #expect(throws: PacketCodecError.unknownVersion(99)) {
            try PacketCodec.decode(encoded)
        }
    }

    @Test func unknownMessageTypeThrows() throws {
        var encoded = try PacketCodec.encode(make(type: .text, body: Data("x".utf8)))
        encoded[1] = 0xFF
        #expect(throws: PacketCodecError.unknownMessageType(0xFF)) {
            try PacketCodec.decode(encoded)
        }
    }

    @Test func payloadLengthMismatchThrows() throws {
        var encoded = try PacketCodec.encode(make(type: .text, body: Data("hi".utf8)))
        encoded[20] = 0x7F
        encoded[21] = 0xFF
        #expect(throws: PacketCodecError.payloadLengthMismatch) {
            try PacketCodec.decode(encoded)
        }
    }
}
