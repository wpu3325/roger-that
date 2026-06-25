import Foundation
import MultipeerConnectivity
import RogerThatCore

private let serviceType = "rogerthat-v1"

/// Multipeer Connectivity link for direct voice delivery.
///
/// Uses ONE shared `MCSession` for the whole channel (peers are added to it as they
/// connect) and an invitation tiebreak so two peers don't both invite each other and
/// spawn competing sessions. Carries VOICE_FRAME and TALK_* packets.
///
/// The link runs for the whole time you're in a channel so you can hear peers the
/// instant they transmit — it is NOT started/stopped per push-to-talk.
final class MultipeerVoiceLink: NSObject, Link, @unchecked Sendable {

    // MARK: - Link

    var peers: [PeerHandle] {
        lock.withLock { Array(connectedPeers.keys) }
    }

    func setHandlers(onReceive: @escaping PacketReceiver, onPeerEvent: @escaping PeerEventHandler) {
        lock.withLock {
            self.onReceive = onReceive
            self.onPeerEvent = onPeerEvent
        }
    }

    func send(_ data: Data, to peer: PeerHandle) {
        let mcPeer = lock.withLock { connectedPeers[peer] }
        guard let mcPeer, let session else { return }
        try? session.send(data, toPeers: [mcPeer], with: .unreliable)
    }

    func broadcast(_ data: Data) {
        guard let session else { return }
        let targets = session.connectedPeers
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .unreliable)
    }

    func start() {
        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        // The serviceType is shared across all channels (its 15-char limit can't hold a
        // hash), so we scope discovery by advertising the channel hash and only connecting
        // peers that match. This keeps two channels in the same room from sharing a voice
        // session. Defence-in-depth: voice frames are also channel-stamped + encrypted.
        let advertiser = MCNearbyServiceAdvertiser(peer: localPeer,
                                                   discoveryInfo: ["ch": channelToken],
                                                   serviceType: serviceType)
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
        advertiser.delegate = self
        browser.delegate = self
        self.advertiser = advertiser
        self.browser = browser

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        lock.withLock { connectedPeers.removeAll() }
    }

    // MARK: - Internal

    let channelIDHash: UInt32
    private let lock = NSLock()
    private let localPeer: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var connectedPeers: [PeerHandle: MCPeerID] = [:]
    private var onReceive: PacketReceiver?
    private var onPeerEvent: PeerEventHandler?

    /// Channel hash as a string, used as the discovery token + invitation context.
    private let channelToken: String

    init(channelIDHash: UInt32, localID: UInt32) {
        self.channelIDHash = channelIDHash
        self.channelToken = String(channelIDHash)
        // MCPeerID displayName must be unique per device so handles don't collide and
        // the invitation tiebreak is deterministic. The user-facing name comes from the
        // BLE presence roster, not from here.
        self.localPeer = MCPeerID(displayName: "RT-\(localID)")
        super.init()
    }

    private func handle(for peer: MCPeerID) -> PeerHandle {
        PeerHandle("mc-\(peer.displayName)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerVoiceLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peer: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept only invitations carrying our channel token (the inviter stamps it as
        // context). Rejects cross-channel or malformed invites.
        guard let context, String(data: context, encoding: .utf8) == channelToken else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerVoiceLink: MCNearbyServiceBrowserDelegate {
    func browser(_ b: MCNearbyServiceBrowser, foundPeer peer: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard let session else { return }
        // Only connect peers advertising our channel — different channels share the
        // serviceType but not the token.
        guard info?["ch"] == channelToken else { return }
        // Tiebreak: only the peer with the larger token invites, so we don't both
        // invite each other and create competing sessions that never stabilize.
        if localPeer.displayName > peer.displayName {
            b.invitePeer(peer, to: session,
                         withContext: Data(channelToken.utf8), timeout: 15)
        }
    }

    func browser(_ b: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        // Connection teardown is handled by session(_:peer:didChange:).
    }
}

// MARK: - MCSessionDelegate

extension MultipeerVoiceLink: MCSessionDelegate {
    func session(_ session: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        let h = handle(for: peer)
        switch state {
        case .connected:
            lock.withLock { connectedPeers[h] = peer }
            lock.withLock { onPeerEvent }?(h, .connected)
        case .notConnected:
            lock.withLock { connectedPeers[h] = nil }
            lock.withLock { onPeerEvent }?(h, .disconnected)
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peer: MCPeerID) {
        lock.withLock { onReceive }?(data, handle(for: peer))
    }

    func session(_ s: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID,
                 with: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID,
                 at: URL?, withError: Error?) {}
}
