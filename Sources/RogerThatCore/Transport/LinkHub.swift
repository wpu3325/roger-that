import Foundation

/// Fans one underlying `Link` out to several independent subscribers.
///
/// `Link.setHandlers` installs a *single* receive handler, so N channels can't each call it
/// on the same transport — the last one wins and the rest go deaf. Multi-channel needs one
/// shared radio (one BLE stack) feeding one `FloodRouter`/`SessionManager` per joined
/// channel. `LinkHub` solves that: it owns the real link, registers itself as the sole
/// handler, and vends lightweight `Link` "ports". Each port has its own handlers; the hub
/// delivers every received packet and peer event to *all* ports (each router then keeps only
/// its own channel via the `channelIDHash` filter). Sends/broadcasts from any port go
/// straight to the shared transport.
///
/// Pure `Link`-protocol logic — unit-tested with `InMemoryLink`, no platform deps.
public final class LinkHub: @unchecked Sendable {

    private let base: any Link
    private let lock = NSLock()
    private var ports: [Port] = []

    public init(base: any Link) {
        self.base = base
        base.setHandlers(
            onReceive: { [weak self] data, peer in self?.fanOutReceive(data, peer) },
            onPeerEvent: { [weak self] peer, event in self?.fanOutPeerEvent(peer, event) }
        )
    }

    /// Vend a virtual link sharing the base transport but with independent handlers.
    public func makePort() -> any Link {
        let port = Port(hub: self)
        lock.withLock { ports.append(port) }
        return port
    }

    /// Stop fanning out to a port (call when leaving that channel).
    public func removePort(_ port: any Link) {
        guard let target = port as? Port else { return }
        lock.withLock { ports.removeAll { $0 === target } }
    }

    /// Start/stop the shared transport. Ports don't control base lifecycle — the owner
    /// (AppState) drives this once for all channels.
    public func start() { base.start() }
    public func stop() { base.stop() }

    // MARK: - Port → base bridge

    fileprivate var basePeers: [PeerHandle] { base.peers }
    fileprivate func baseSend(_ data: Data, to peer: PeerHandle) { base.send(data, to: peer) }
    fileprivate func baseBroadcast(_ data: Data) { base.broadcast(data) }

    // MARK: - Fan-out

    private func fanOutReceive(_ data: Data, _ peer: PeerHandle) {
        let snapshot = lock.withLock { ports }
        for port in snapshot { port.deliverReceive(data, peer) }
    }

    private func fanOutPeerEvent(_ peer: PeerHandle, _ event: PeerEvent) {
        let snapshot = lock.withLock { ports }
        for port in snapshot { port.deliverPeerEvent(peer, event) }
    }

    // MARK: - Port

    /// A virtual `Link` over the hub's shared transport.
    public final class Port: Link, @unchecked Sendable {
        private weak var hub: LinkHub?
        private let lock = NSLock()
        private var onReceive: PacketReceiver?
        private var onPeerEvent: PeerEventHandler?

        fileprivate init(hub: LinkHub) { self.hub = hub }

        public var peers: [PeerHandle] { hub?.basePeers ?? [] }

        public func setHandlers(onReceive: @escaping PacketReceiver, onPeerEvent: @escaping PeerEventHandler) {
            lock.withLock {
                self.onReceive = onReceive
                self.onPeerEvent = onPeerEvent
            }
        }

        public func send(_ data: Data, to peer: PeerHandle) { hub?.baseSend(data, to: peer) }
        public func broadcast(_ data: Data) { hub?.baseBroadcast(data) }

        // A single port must not start/stop the shared transport — the hub owns that.
        public func start() {}
        public func stop() {}

        fileprivate func deliverReceive(_ data: Data, _ peer: PeerHandle) {
            let handler = lock.withLock { onReceive }
            handler?(data, peer)
        }

        fileprivate func deliverPeerEvent(_ peer: PeerHandle, _ event: PeerEvent) {
            let handler = lock.withLock { onPeerEvent }
            handler?(peer, event)
        }
    }
}
