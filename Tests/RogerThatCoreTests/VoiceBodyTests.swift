import Testing
import Foundation
import CryptoKit
@testable import RogerThatCore

@Suite("VoiceBody")
struct VoiceBodyTests {

    private func makeCrypto() -> ChannelCrypto { ChannelCrypto(key: ChannelCrypto.generateKey()) }
    private var sampleFrame: Data { Data((0..<640).map { UInt8($0 & 0xFF) }) }

    @Test func sealOpenRoundTrip() throws {
        let crypto = makeCrypto()
        let sealed = try VoiceBody.seal(sessionID: 0xDEADBEEF, seq: 42, frame: sampleFrame, crypto: crypto)
        let opened = VoiceBody.open(sealed, crypto: crypto)
        #expect(opened?.sessionID == 0xDEADBEEF)
        #expect(opened?.seq == 42)
        #expect(opened?.frame == sampleFrame)
    }

    @Test func sealedBodyIsEncrypted() throws {
        let crypto = makeCrypto()
        let sealed = try VoiceBody.seal(sessionID: 1, seq: 1, frame: sampleFrame, crypto: crypto)
        // Ciphertext must not contain the raw frame bytes.
        #expect(sealed != VoiceBody.pack(sessionID: 1, seq: 1, frame: sampleFrame))
        #expect(sealed.count == sampleFrame.count + 8 + 28)   // header + nonce(12)+tag(16)
    }

    @Test func wrongKeyRejected() throws {
        let sealed = try VoiceBody.seal(sessionID: 1, seq: 1, frame: sampleFrame, crypto: makeCrypto())
        #expect(VoiceBody.open(sealed, crypto: makeCrypto()) == nil)
    }

    @Test func tamperRejected() throws {
        let crypto = makeCrypto()
        var sealed = try VoiceBody.seal(sessionID: 1, seq: 1, frame: sampleFrame, crypto: crypto)
        sealed[sealed.count - 1] ^= 0x01
        #expect(VoiceBody.open(sealed, crypto: crypto) == nil)
    }

    @Test func shortBodyRejected() {
        #expect(VoiceBody.open(Data([1, 2, 3]), crypto: makeCrypto()) == nil)
    }

    @Test func emptyFrameRoundTrips() throws {
        let crypto = makeCrypto()
        let sealed = try VoiceBody.seal(sessionID: 7, seq: 0, frame: Data(), crypto: crypto)
        let opened = VoiceBody.open(sealed, crypto: crypto)
        #expect(opened?.sessionID == 7)
        #expect(opened?.seq == 0)
        #expect(opened?.frame.isEmpty == true)
    }
}
