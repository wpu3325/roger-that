import Foundation
import CryptoKit

/// AEAD encryption/decryption for packet bodies using ChaChaPoly.
///
/// Wire format: nonce(12) ‖ ciphertext ‖ tag(16)
public final class ChannelCrypto: Sendable {

    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    /// Generate a fresh 256-bit symmetric key.
    public static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Serialize a SymmetricKey to raw bytes.
    public static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Reconstruct a SymmetricKey from raw bytes.
    public static func key(from data: Data) -> SymmetricKey? {
        guard data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    public func encrypt(_ plaintext: Data) throws -> Data {
        let nonce = ChaChaPoly.Nonce()
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce)
        // nonce(12) + ciphertext + tag(16)
        var out = Data(sealed.nonce)
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    public func decrypt(_ combined: Data) throws -> Data {
        // Minimum: 12 (nonce) + 0 (ct) + 16 (tag) = 28 bytes
        guard combined.count >= 28 else { throw CryptoError.invalidLength }
        let box = try ChaChaPoly.SealedBox(combined: combined)
        return try ChaChaPoly.open(box, using: key)
    }
}

public enum CryptoError: Error {
    case invalidLength
}
