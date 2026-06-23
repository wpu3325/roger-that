import Foundation

/// Callback type for received packets and peer lifecycle events.
public typealias PacketReceiver = @Sendable (Data, PeerHandle) -> Void
public typealias PeerEventHandler = @Sendable (PeerHandle, PeerEvent) -> Void

public enum PeerEvent: Sendable {
    case connected
    case disconnected
}

/// Abstraction over any point-to-point transport.
///
/// Implementations: InMemoryLink (tests), BLEMeshLink, MultipeerVoiceLink (device).
/// Must not be imported in RogerThatCore — only the protocol lives here.
public protocol Link: AnyObject, Sendable {
    /// Currently reachable direct peers.
    var peers: [PeerHandle] { get }

    /// Register callbacks for incoming data and peer lifecycle.
    func setHandlers(onReceive: @escaping PacketReceiver, onPeerEvent: @escaping PeerEventHandler)

    /// Send raw bytes to a specific peer; fire-and-forget.
    func send(_ data: Data, to peer: PeerHandle)

    /// Broadcast raw bytes to all current peers.
    func broadcast(_ data: Data)

    /// Start the link (begin scanning/advertising).
    func start()

    /// Stop the link.
    func stop()
}
