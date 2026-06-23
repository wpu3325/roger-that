import Testing
import Foundation
import CryptoKit
@testable import RogerThatCore

@Suite("JoinCode")
struct JoinCodeTests {

    // MARK: - Round-trip

    @Test func roundTrip() throws {
        let channel = Channel.create()
        let code = try JoinPayload(channel: channel).encode()
        let decoded = try JoinPayload.decode(code)
        #expect(decoded.channelID == channel.channelID)
        // Keys are equivalent if encrypt/decrypt works across them.
        let plain = Data("verify".utf8)
        let cipher = try ChannelCrypto(key: channel.key).encrypt(plain)
        let decrypted = try ChannelCrypto(key: decoded.key).decrypt(cipher)
        #expect(decrypted == plain)
    }

    @Test func toChannelPreservesHash() throws {
        let original = Channel.create()
        let code = try JoinPayload(channel: original).encode()
        let recovered = try JoinPayload.decode(code).toChannel()
        #expect(recovered.channelID == original.channelID)
        #expect(recovered.channelIDHash == original.channelIDHash)
    }

    // MARK: - URL-safe base64

    @Test func urlSafeOutput() throws {
        for _ in 0..<10 {
            let code = try JoinPayload(channel: Channel.create()).encode()
            #expect(!code.contains("+"))
            #expect(!code.contains("/"))
            #expect(!code.contains("="))
        }
    }

    // MARK: - Error cases

    @Test func invalidBase64Throws() {
        #expect(throws: JoinCodeError.invalidBase64) {
            try JoinPayload.decode("!!!invalid!!!")
        }
    }

    @Test func tooShortThrows() {
        let short = Data(repeating: 0, count: 10).base64EncodedString()
        #expect(throws: JoinCodeError.invalidLength) {
            try JoinPayload.decode(short)
        }
    }

    @Test func truncatedPayloadThrows() {
        var data = Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        var length = UInt32(100).littleEndian
        Swift.withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(Data("short".utf8))
        #expect(throws: JoinCodeError.invalidLength) {
            try JoinPayload.decode(data.base64EncodedString())
        }
    }

    // MARK: - Channel hash

    @Test func hashDeterministic() {
        let id = "test-channel-id"
        #expect(Channel.hash(id) == Channel.hash(id))
    }

    @Test func differentIDsDifferentHashes() {
        #expect(Channel.hash("channel-a") != Channel.hash("channel-b"))
    }
}
