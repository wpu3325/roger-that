import Foundation
import CryptoKit

/// A joined channel. Carries the channel id string, its u32 hash (used in headers),
/// and the shared symmetric key for body encryption.
public struct Channel: Sendable {
    public let channelID: String
    public let channelIDHash: UInt32
    public let key: SymmetricKey

    public init(channelID: String, key: SymmetricKey) {
        self.channelID = channelID
        self.channelIDHash = Channel.hash(channelID)
        self.key = key
    }

    /// Create a brand-new channel with a random id and key.
    public static func create() -> Channel {
        let id = UUID().uuidString
        let key = ChannelCrypto.generateKey()
        return Channel(channelID: id, key: key)
    }

    /// Truncated FNV-1a hash of the channel id string.
    static func hash(_ id: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return hash
    }
}
