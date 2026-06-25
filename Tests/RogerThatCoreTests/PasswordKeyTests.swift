import Testing
import Foundation
import CryptoKit
@testable import RogerThatCore

@Suite("PasswordKey")
struct PasswordKeyTests {

    private func keyHex(_ k: SymmetricKey) -> String {
        k.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
    }

    /// Standard PBKDF2-HMAC-SHA256 vectors (password="password", salt="salt").
    @Test func matchesPBKDF2TestVectors() {
        #expect(keyHex(PasswordKey.deriveKey(name: "salt", password: "password", iterations: 1))
                == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        #expect(keyHex(PasswordKey.deriveKey(name: "salt", password: "password", iterations: 2))
                == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        #expect(keyHex(PasswordKey.deriveKey(name: "salt", password: "password", iterations: 4096))
                == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    @Test func sameNameAndPasswordYieldSameChannel() {
        let a = PasswordKey.channel(name: "Ski Trip", password: "powder2026", iterations: 2000)
        let b = PasswordKey.channel(name: "Ski Trip", password: "powder2026", iterations: 2000)
        #expect(a.channelID == b.channelID)
        #expect(a.channelIDHash == b.channelIDHash)
        #expect(keyHex(a.key) == keyHex(b.key))
    }

    @Test func differentPasswordFullySeparates() {
        let a = PasswordKey.channel(name: "Ski Trip", password: "powder2026", iterations: 2000)
        let c = PasswordKey.channel(name: "Ski Trip", password: "wrong", iterations: 2000)
        #expect(c.channelID != a.channelID)
        #expect(c.channelIDHash != a.channelIDHash)   // no discovery collision either
    }

    @Test func differentNameYieldsDifferentChannel() {
        let a = PasswordKey.channel(name: "Ski Trip", password: "p", iterations: 2000)
        let b = PasswordKey.channel(name: "Hike", password: "p", iterations: 2000)
        #expect(a.channelID != b.channelID)
    }

    @Test func fingerprintMatchesForSameKeyDiffersOtherwise() {
        let a = PasswordKey.channel(name: "Ski Trip", password: "powder2026", iterations: 2000)
        let b = PasswordKey.channel(name: "Ski Trip", password: "powder2026", iterations: 2000)
        let c = PasswordKey.channel(name: "Ski Trip", password: "typo", iterations: 2000)
        #expect(PasswordKey.fingerprint(of: a.key) == PasswordKey.fingerprint(of: b.key))
        #expect(PasswordKey.fingerprint(of: a.key) != PasswordKey.fingerprint(of: c.key))
        #expect(PasswordKey.fingerprint(of: a.key).count == 9)   // "XXXX·XXXX"
    }

    @Test func derivedKeyWorksForChannelCrypto() throws {
        let channel = PasswordKey.channel(name: "Ski Trip", password: "powder2026", iterations: 2000)
        let crypto = ChannelCrypto(key: channel.key)
        let plain = Data("hello".utf8)
        #expect(try crypto.decrypt(try crypto.encrypt(plain)) == plain)
    }
}
