import Foundation
import CryptoKit

/// Derives a channel from a human channel **name + password**, so a group can join by
/// agreeing on those two strings instead of scanning a QR.
///
/// Same `(name, password)` → the same `Channel` (same id, key, and hash) on every device,
/// which is exactly what makes "join by password" work. The key comes from PBKDF2-HMAC-
/// SHA256 (a deliberately slow KDF) to blunt brute force on low-entropy passwords; the salt
/// is the channel name (shared, not secret — it only needs to be unique per channel).
///
/// The channelID is derived from the *key*, so two channels that share a name but not a
/// password don't even collide on `channelIDHash` — they never discover each other.
///
/// Pure CryptoKit (no platform deps) so it lives in Core and is unit-tested against the
/// standard PBKDF2 test vectors.
public enum PasswordKey {

    /// Default PBKDF2 iteration count. High enough to slow brute force, fast enough that
    /// joining is near-instant on a phone.
    public static let defaultIterations = 100_000

    /// Build the channel for a name + password.
    public static func channel(name: String, password: String,
                               iterations: Int = defaultIterations) -> Channel {
        let key = deriveKey(name: name, password: password, iterations: iterations)
        return Channel(channelID: channelID(for: key), key: key)
    }

    /// The 32-byte channel key for a name + password.
    public static func deriveKey(name: String, password: String,
                                 iterations: Int = defaultIterations) -> SymmetricKey {
        let derived = pbkdf2SHA256(password: Data(password.utf8),
                                   salt: Data(name.utf8),
                                   iterations: max(1, iterations))
        return SymmetricKey(data: derived)
    }

    /// A short, non-secret fingerprint of a channel key (e.g. "A1B2·C3D4"). Show it on both
    /// the create and join screens so people can eyeball-confirm they derived the same key —
    /// i.e. typed the same password — instead of silently landing in different channels.
    public static func fingerprint(of key: SymmetricKey) -> String {
        let fp = HKDF<SHA256>.deriveKey(inputKeyMaterial: key,
                                        info: Data("rogerthat-fingerprint".utf8),
                                        outputByteCount: 4)
        let hex = fp.withUnsafeBytes { Data($0) }.map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(4))·\(hex.suffix(4))"
    }

    // MARK: - Private

    /// Opaque channelID tied to the exact derived key (so different passwords fully separate).
    private static func channelID(for key: SymmetricKey) -> String {
        let id = HKDF<SHA256>.deriveKey(inputKeyMaterial: key,
                                        info: Data("rogerthat-channel-id".utf8),
                                        outputByteCount: 8)
        return "pw-" + id.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
    }

    /// PBKDF2-HMAC-SHA256 producing a 32-byte key. Since the output length equals the
    /// SHA-256 block (32 bytes), this is a single PBKDF2 block: T_1 = U_1 ⊕ U_2 ⊕ … ⊕ U_c.
    private static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int) -> Data {
        let key = SymmetricKey(data: password)
        // U_1 = HMAC(password, salt ‖ INT32_BE(1))
        var salted = salt
        salted.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        var u = Data(HMAC<SHA256>.authenticationCode(for: salted, using: key))
        var result = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                for i in 0..<result.count { result[i] ^= u[i] }
            }
        }
        return result
    }
}
