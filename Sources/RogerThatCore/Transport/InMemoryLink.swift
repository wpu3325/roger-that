import Foundation

/// In-process link used exclusively for unit tests.
///
/// Nodes are wired together via `connect(to:)` which forms a bidirectional edge.
/// All delivery is synchronous (no async dispatch) so tests are deterministic.
public final class InMemoryLink: Link, @unchecked Sendable {

    public let handle: PeerHandle
    private let lock = NSLock()

    private var _peers: [PeerHandle: InMemoryLink] = [:]
    private var onReceive: PacketReceiver?
    private var onPeerEvent: PeerEventHandler?

    public var peers: [PeerHandle] {
        lock.withLock { Array(_peers.keys) }
    }

    public init(id: String) {
        handle = PeerHandle(id)
    }

    public func setHandlers(onReceive: @escaping PacketReceiver, onPeerEvent: @escaping PeerEventHandler) {
        lock.withLock {
            self.onReceive = onReceive
            self.onPeerEvent = onPeerEvent
        }
    }

    /// Wire a bidirectional edge between this node and `other`.
    public func connect(to other: InMemoryLink) {
        lock.withLock { _peers[other.handle] = other }
        other.lock.withLock { other._peers[handle] = self }
        notifyPeerEvent(.connected, for: other.handle)
        other.notifyPeerEvent(.connected, for: handle)
    }

    /// Remove the edge between this node and `other`.
    public func disconnect(from other: InMemoryLink) {
        lock.withLock { _peers.removeValue(forKey: other.handle) }
        other.lock.withLock { other._peers.removeValue(forKey: handle) }
        notifyPeerEvent(.disconnected, for: other.handle)
        other.notifyPeerEvent(.disconnected, for: handle)
    }

    public func send(_ data: Data, to peer: PeerHandle) {
        let target = lock.withLock { _peers[peer] }
        target?.deliver(data, from: handle)
    }

    public func broadcast(_ data: Data) {
        let targets = lock.withLock { Array(_peers.values) }
        for target in targets {
            target.deliver(data, from: handle)
        }
    }

    public func start() {}
    public func stop() {}

    // MARK: - Internal

    func deliver(_ data: Data, from sender: PeerHandle) {
        let handler = lock.withLock { onReceive }
        handler?(data, sender)
    }

    private func notifyPeerEvent(_ event: PeerEvent, for peer: PeerHandle) {
        let handler = lock.withLock { onPeerEvent }
        handler?(peer, event)
    }
}

// MARK: - NSLock convenience

extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
