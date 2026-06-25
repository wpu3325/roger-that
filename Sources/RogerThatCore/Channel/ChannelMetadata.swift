import Foundation

/// Persisted record of a joined channel — everything *except* the secret key, which is
/// stored separately (in the Keychain on device) under `channelID`.
///
/// `Codable` so the app can save the joined-channels list (order preserved) as JSON in
/// UserDefaults; `kind` distinguishes a random-key channel (shared by QR/code) from a
/// password-derived one (shared by name + password — see Phase 4).
public struct ChannelMetadata: Sendable, Equatable, Codable, Identifiable {

    public enum Kind: String, Sendable, Codable {
        /// Key is random; the only way in is the QR / invite code.
        case random
        /// Key is derived from the channel name + a password.
        case password
    }

    public let channelID: String
    public var name: String
    public let kind: Kind
    public let joinedAt: Date

    public var id: String { channelID }

    public init(channelID: String, name: String, kind: Kind, joinedAt: Date) {
        self.channelID = channelID
        self.name = name
        self.kind = kind
        self.joinedAt = joinedAt
    }
}
