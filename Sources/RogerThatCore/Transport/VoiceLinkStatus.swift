import Foundation

/// Why the voice link can't carry audio — authoritative signals the UI can act on.
public enum VoiceUnavailableReason: Equatable, Sendable {
    /// Local Network permission was denied (Multipeer can't discover/advertise).
    case localNetworkDenied
    /// Microphone permission was denied (capture can't start).
    case microphoneDenied
}

/// User-facing state of the Multipeer voice link, surfaced so failures are never silent.
public enum VoiceLinkStatus: Equatable, Sendable {
    /// Started, handshaking, nobody connected yet.
    case connecting
    /// At least one peer is fully connected.
    case connected(peers: Int)
    /// We've been searching a while and found nobody (informational, not an error).
    case noPeers
    /// A hard blocker the user must resolve (permissions).
    case unavailable(VoiceUnavailableReason)

    /// Derive status from live counts + how long we've been trying.
    ///
    /// Permission denial is a separate, authoritative input (it can't be inferred from
    /// counts), so the caller sets `.unavailable` directly; this only maps the
    /// connecting / connected / noPeers cases.
    public static func evaluate(connected: Int,
                                connecting: Int,
                                elapsed: TimeInterval,
                                noPeerThreshold: TimeInterval) -> VoiceLinkStatus {
        if connected > 0 { return .connected(peers: connected) }
        if connecting > 0 { return .connecting }
        return elapsed >= noPeerThreshold ? .noPeers : .connecting
    }
}
