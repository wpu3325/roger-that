import Foundation
import MultipeerConnectivity
import RogerThatCore

private let serviceType = "rogerthat-v1"

/// Multipeer Connectivity link for direct voice delivery.
///
/// Uses ONE shared `MCSession` for the whole channel and a strict invitation tiebreak (only
/// the peer with the larger `displayName` invites) so two peers don't form competing sessions.
/// That rule alone deadlocks if the single invite is missed/declined/timed-out, so a repeating
/// retry timer re-invites discovered-but-unconnected peers with backoff (`MultipeerRetryPolicy`),
/// and the non-inviter steps in as a late fallback. Carries VOICE_FRAME and TALK_* packets.
///
/// The link runs the whole time you're in a channel so you can hear peers the instant they
/// transmit — it is NOT started/stopped per push-to-talk.
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

    /// Voice-link-specific status stream (connecting / connected / noPeers / unavailable).
    /// Separate from `Link` so we don't widen the protocol BLE shares.
    func setStatusHandler(_ handler: @escaping @Sendable (VoiceLinkStatus) -> Void) {
        lock.withLock { onStatusChange = handler }
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
        startedAt = Date()
        unavailableReason = nil

        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        // The serviceType is shared across all channels (its 15-char limit can't hold a
        // hash), so we scope discovery by advertising the channel hash and only connecting
        // peers that match. Defence-in-depth: voice frames are also channel-stamped + encrypted.
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

        startRetryTimer()
        recomputeStatus()
    }

    func stop() {
        retryTimer?.cancel()
        retryTimer = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        lock.withLock {
            connectedPeers.removeAll()
            discovered.removeAll()
        }
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
    private var onStatusChange: (@Sendable (VoiceLinkStatus) -> Void)?

    /// Channel hash as a string, used as the discovery token + invitation context.
    private let channelToken: String

    // Retry / status state (all under `lock`).
    private enum Phase { case discovered, connecting, connected }
    private struct PeerProgress {
        let firstSeen: Date
        var lastInviteAt: Date?
        var attempts: Int
        var phase: Phase
    }
    private var discovered: [MCPeerID: PeerProgress] = [:]
    private let policy = MultipeerRetryPolicy()
    private let noPeerThreshold: TimeInterval = 8
    private var startedAt = Date()
    private var unavailableReason: VoiceUnavailableReason?

    private var retryTimer: DispatchSourceTimer?
    private let retryQueue = DispatchQueue(label: "com.rogerthat.voice.retry", qos: .utility)

    init(channelIDHash: UInt32, localID: UInt32) {
        self.channelIDHash = channelIDHash
        self.channelToken = String(channelIDHash)
        // MCPeerID displayName must be unique per device so handles don't collide and the
        // invitation tiebreak is deterministic. User-facing names come from the BLE roster.
        self.localPeer = MCPeerID(displayName: "RT-\(localID)")
        super.init()
    }

    private func handle(for peer: MCPeerID) -> PeerHandle {
        PeerHandle("mc-\(peer.displayName)")
    }

    // MARK: - Retry loop

    private func startRetryTimer() {
        let timer = DispatchSource.makeTimerSource(queue: retryQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.retryTick() }
        timer.resume()
        retryTimer = timer
    }

    /// Re-invite any discovered peer that isn't connected yet and is due per the policy.
    private func retryTick() {
        let now = Date()
        let toInvite: [MCPeerID] = lock.withLock {
            discovered.compactMap { (peer, progress) in
                guard progress.phase != .connected else { return nil }
                let isPrimary = localPeer.displayName > peer.displayName
                guard policy.shouldInvite(isPrimaryInviter: isPrimary, attempts: progress.attempts,
                                          lastInviteAt: progress.lastInviteAt,
                                          firstSeen: progress.firstSeen, now: now) else { return nil }
                return peer
            }
        }
        for peer in toInvite { invite(peer, at: now) }
        recomputeStatus()
    }

    private func invite(_ peer: MCPeerID, at now: Date) {
        guard let session, let browser else { return }
        lock.withLock {
            discovered[peer]?.lastInviteAt = now
            discovered[peer]?.attempts += 1
            if discovered[peer]?.phase == .discovered { discovered[peer]?.phase = .connecting }
        }
        browser.invitePeer(peer, to: session, withContext: Data(channelToken.utf8), timeout: 10)
    }

    // MARK: - Status

    private func recomputeStatus() {
        let status: VoiceLinkStatus = lock.withLock {
            if let reason = unavailableReason { return .unavailable(reason) }
            let connected = connectedPeers.count
            let connecting = discovered.values.filter { $0.phase == .connecting }.count
            let elapsed = Date().timeIntervalSince(startedAt)
            return VoiceLinkStatus.evaluate(connected: connected, connecting: connecting,
                                            elapsed: elapsed, noPeerThreshold: noPeerThreshold)
        }
        let handler = lock.withLock { onStatusChange }
        handler?(status)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerVoiceLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peer: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept only invitations carrying our channel token (the inviter stamps it as context).
        guard let context, String(data: context, encoding: .utf8) == channelToken else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        // Fires when Local Network permission is denied (or Bonjour can't publish).
        lock.withLock { unavailableReason = .localNetworkDenied }
        recomputeStatus()
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerVoiceLink: MCNearbyServiceBrowserDelegate {
    func browser(_ b: MCNearbyServiceBrowser, foundPeer peer: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        // Only consider peers advertising our channel — different channels share serviceType.
        guard info?["ch"] == channelToken else { return }
        let now = Date()
        lock.withLock {
            if discovered[peer] == nil {
                discovered[peer] = PeerProgress(firstSeen: now, lastInviteAt: nil,
                                                attempts: 0, phase: .discovered)
            }
        }
        // Invite immediately if the policy allows (primary inviter, never tried); otherwise the
        // retry timer picks it up.
        let isPrimary = localPeer.displayName > peer.displayName
        let progress = lock.withLock { discovered[peer] }
        if let progress,
           policy.shouldInvite(isPrimaryInviter: isPrimary, attempts: progress.attempts,
                               lastInviteAt: progress.lastInviteAt,
                               firstSeen: progress.firstSeen, now: now) {
            invite(peer, at: now)
        }
        recomputeStatus()
    }

    func browser(_ b: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        // Truly gone — stop retrying it. (Connection teardown for a *connected* peer comes
        // through session(_:peer:didChange:) instead.)
        lock.withLock { discovered[peer] = nil }
        recomputeStatus()
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        lock.withLock { unavailableReason = .localNetworkDenied }
        recomputeStatus()
    }
}

// MARK: - MCSessionDelegate

extension MultipeerVoiceLink: MCSessionDelegate {
    func session(_ session: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        let h = handle(for: peer)
        switch state {
        case .connected:
            lock.withLock {
                connectedPeers[h] = peer
                discovered[peer]?.phase = .connected
                discovered[peer]?.attempts = 0
            }
            (lock.withLock { onPeerEvent })?(h, .connected)
        case .connecting:
            lock.withLock { discovered[peer]?.phase = .connecting }
        case .notConnected:
            lock.withLock {
                connectedPeers[h] = nil
                // Keep it in `discovered` (if still nearby) so the retry timer re-invites it;
                // mark it back to .discovered so it's eligible.
                if discovered[peer] != nil { discovered[peer]?.phase = .discovered }
            }
            (lock.withLock { onPeerEvent })?(h, .disconnected)
        @unknown default:
            break
        }
        recomputeStatus()
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peer: MCPeerID) {
        (lock.withLock { onReceive })?(data, handle(for: peer))
    }

    func session(_ s: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID,
                 with: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID,
                 at: URL?, withError: Error?) {}
}
