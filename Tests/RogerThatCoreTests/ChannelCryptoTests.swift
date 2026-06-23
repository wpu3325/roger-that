import Testing
import Foundation
import CryptoKit
@testable import RogerThatCore

@Suite("ChannelCrypto")
struct ChannelCryptoTests {

    // MARK: - Key

    @Test func keyGenerationLength() {
        let data = ChannelCrypto.keyData(ChannelCrypto.generateKey())
        #expect(data.count == 32)
    }

    @Test func keyRoundTrip() throws {
        let original = ChannelCrypto.generateKey()
        let data = ChannelCrypto.keyData(original)
        let restored = try #require(ChannelCrypto.key(from: data))
        let plain = Data("roundtrip".utf8)
        let cipher = try ChannelCrypto(key: original).encrypt(plain)
        let decrypted = try ChannelCrypto(key: restored).decrypt(cipher)
        #expect(decrypted == plain)
    }

    @Test func keyFromShortDataReturnsNil() {
        #expect(ChannelCrypto.key(from: Data([1, 2])) == nil)
    }

    @Test func keyFromEmptyDataReturnsNil() {
        #expect(ChannelCrypto.key(from: Data()) == nil)
    }

    // MARK: - Round-trips

    @Test func roundTripShortMessage() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plain = Data("Hello".utf8)
        #expect(try crypto.decrypt(crypto.encrypt(plain)) == plain)
    }

    @Test func roundTripEmptyMessage() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        #expect(try crypto.decrypt(crypto.encrypt(Data())) == Data())
    }

    @Test func roundTripBinaryData() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plain = Data((0..<1024).map { UInt8($0 & 0xFF) })
        #expect(try crypto.decrypt(crypto.encrypt(plain)) == plain)
    }

    // MARK: - Nonce uniqueness

    @Test func freshNonceEachEncrypt() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plain = Data("same".utf8)
        let c1 = try crypto.encrypt(plain)
        let c2 = try crypto.encrypt(plain)
        #expect(c1 != c2)
    }

    // MARK: - Tamper rejection

    @Test func tamperedCiphertextFails() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        var cipher = try crypto.encrypt(Data("secret".utf8))
        cipher[15] ^= 0xFF
        #expect(throws: (any Error).self) { try crypto.decrypt(cipher) }
    }

    @Test func tamperedTagFails() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        var cipher = try crypto.encrypt(Data("secret".utf8))
        cipher[cipher.count - 1] ^= 0x01
        #expect(throws: (any Error).self) { try crypto.decrypt(cipher) }
    }

    @Test func truncatedCiphertextFails() {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        #expect(throws: (any Error).self) {
            try crypto.decrypt(Data(repeating: 0, count: 27))
        }
    }

    @Test func wrongKeyFails() throws {
        let enc = ChannelCrypto(key: ChannelCrypto.generateKey())
        let dec = ChannelCrypto(key: ChannelCrypto.generateKey())
        let cipher = try enc.encrypt(Data("secret".utf8))
        #expect(throws: (any Error).self) { try dec.decrypt(cipher) }
    }

    // MARK: - Wire format

    @Test func ciphertextLengthForOneByte() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let cipher = try crypto.encrypt(Data("x".utf8))
        // 12 (nonce) + 1 (ct) + 16 (tag) = 29
        #expect(cipher.count == 29)
    }
}
