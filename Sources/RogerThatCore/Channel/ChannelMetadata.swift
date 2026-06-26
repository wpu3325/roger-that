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
    /// `true` once the user "leaves" the channel: the session stops and it moves to the
    /// Archived section, but its key + message history are kept (reopening rejoins).
    /// "Delete" is the separate destructive action that scrubs everything.
    public var isArchived: Bool

    public var id: String { channelID }

    public init(channelID: String, name: String, kind: Kind, joinedAt: Date, isArchived: Bool = false) {
        self.channelID = channelID
        self.name = name
        self.kind = kind
        self.joinedAt = joinedAt
        self.isArchived = isArchived
    }

    // Custom decode so channels saved before `isArchived` existed still load (default false).
    private enum CodingKeys: String, CodingKey {
        case channelID, name, kind, joinedAt, isArchived
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try c.decode(String.self, forKey: .channelID)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        joinedAt = try c.decode(Date.self, forKey: .joinedAt)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}
