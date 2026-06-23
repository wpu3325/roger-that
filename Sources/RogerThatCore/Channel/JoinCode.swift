import Foundation
import CryptoKit

/// Errors during join-code encoding/decoding.
public enum JoinCodeError: Error, Sendable, Equatable {
    case invalidBase64
    case invalidLength
    case invalidUTF8
}

/// Compact payload that encodes everything needed to join a channel.
///
/// Binary layout (all fields little-endian):
///   [32 bytes] symmetric key
///   [4  bytes] channelID length (UInt32 LE)
///   [N  bytes] channelID UTF-8
///
/// Serialized to/from URL-safe base64 for QR codes and short links.
public struct JoinPayload: Sendable {
    public let channelID: String
    public let key: SymmetricKey

    public init(channelID: String, key: SymmetricKey) {
        self.channelID = channelID
        self.key = key
    }

    public init(channel: Channel) {
        self.channelID = channel.channelID
        self.key = channel.key
    }

    // MARK: - Encode

    public func encode() throws -> String {
        var data = ChannelCrypto.keyData(key)            // 32 bytes
        let idBytes = Data(channelID.utf8)
        var idLen = UInt32(idBytes.count).littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &idLen) { Data($0) })
        data.append(idBytes)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Decode

    public static func decode(_ code: String) throws -> JoinPayload {
        // Re-pad and restore standard base64 chars.
        var b64 = code
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem != 0 { b64 += String(repeating: "=", count: 4 - rem) }

        guard let data = Data(base64Encoded: b64) else {
            throw JoinCodeError.invalidBase64
        }

        // Minimum: 32 (key) + 4 (len) + 0 (id) = 36 bytes
        guard data.count >= 36 else { throw JoinCodeError.invalidLength }

        let key = SymmetricKey(data: data[0 ..< 32])

        var idLen: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &idLen) { ptr in
            data[32 ..< 36].copyBytes(to: ptr)
        }
        idLen = UInt32(littleEndian: idLen)

        guard data.count >= 36 + Int(idLen) else { throw JoinCodeError.invalidLength }

        let idData = data[36 ..< 36 + Int(idLen)]
        guard let channelID = String(data: idData, encoding: .utf8) else {
            throw JoinCodeError.invalidUTF8
        }

        return JoinPayload(channelID: channelID, key: key)
    }

    public func toChannel() -> Channel {
        Channel(channelID: channelID, key: key)
    }
}
