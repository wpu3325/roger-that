import Foundation
import MultipeerConnectivity
import RogerThatCore

private let serviceType = "rogerthat-v1"

/// On-demand Multipeer Connectivity link for direct voice delivery.
///
/// Brought up on TALK_START, torn down after TALK_END + a short grace period.
/// Only carries VOICE_FRAME and TALK_* packets to directly-connected peers.
final class MultipeerVoiceLink: NSObject, Link {

    // MARK: - Link

    var peers: [PeerHandle] {
        lock.withLock { Array(sessions.keys) }
    }

    func setHandlers(onReceive: @escaping PacketReceiver, onPeerEvent: @escaping PeerEventHandler) {
        lock.withLock {
            self.onReceive = onReceive
            self.onPeerEvent = onPeerEvent
        }
    }

    func send(_ data: Data, to peer: PeerHandle) {
        let session = lock.withLock { sessions[peer] }
        let mcPeer = lock.withLock { peerHandleMap[peer] }
        guard let s = session, let p = mcPeer else { return }
        try? s.send(data, toPeers: [p], with: .unreliable)
    }

    func broadcast(_ data: Data) {
        for peer in peers { send(data, to: peer) }
    }

    func start() {
        let me = MCPeerID(displayName: UIDevice.current.name)
        localPeer = me
        advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: me, serviceType: serviceType)
        advertiser?.delegate = self
        browser?.delegate = self
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        lock.withLock { sessions.values.forEach { $0.disconnect() } }
        lock.withLock { sessions.removeAll() }
    }

    // MARK: - Internal

    let channelIDHash: UInt32
    private let lock = NSLock()
    private var localPeer: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var sessions: [PeerHandle: MCSession] = [:]
    private var peerHandleMap: [PeerHandle: MCPeerID] = [:]
    private var onReceive: PacketReceiver?
    private var onPeerEvent: PeerEventHandler?

    init(channelIDHash: UInt32) {
        self.channelIDHash = channelIDHash
    }

    private func makeSession(for peer: MCPeerID) -> MCSession {
        let s = MCSession(peer: localPeer ?? peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerVoiceLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peer: MCPeerID,
                    withContext: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let session = makeSession(for: peer)
        let handle = PeerHandle("mc-\(peer.displayName)")
        lock.withLock {
            sessions[handle] = session
            peerHandleMap[handle] = peer
        }
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerVoiceLink: MCNearbyServiceBrowserDelegate {
    func browser(_ b: MCNearbyServiceBrowser, foundPeer peer: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        let session = makeSession(for: peer)
        let handle = PeerHandle("mc-\(peer.displayName)")
        lock.withLock {
            sessions[handle] = session
            peerHandleMap[handle] = peer
        }
        b.invitePeer(peer, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ b: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        let handle = PeerHandle("mc-\(peer.displayName)")
        lock.withLock {
            sessions.removeValue(forKey: handle)
            peerHandleMap.removeValue(forKey: handle)
        }
        lock.withLock { onPeerEvent }?(handle, .disconnected)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerVoiceLink: MCSessionDelegate {
    func session(_ session: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        let handle = PeerHandle("mc-\(peer.displayName)")
        let event: PeerEvent = state == .connected ? .connected : .disconnected
        lock.withLock { onPeerEvent }?(handle, event)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peer: MCPeerID) {
        let handle = PeerHandle("mc-\(peer.displayName)")
        lock.withLock { onReceive }?(data, handle)
    }

    func session(_ s: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID,
                 with: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID,
                 at: URL?, withError: Error?) {}
}

// MARK: - UIDevice import

import UIKit
