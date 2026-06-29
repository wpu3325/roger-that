import Foundation

/// Decides when this device should (re)send a Multipeer invitation to a discovered peer.
///
/// The voice link keeps ONE shared session and a strict "larger displayName invites" rule to
/// avoid two peers forming competing/crossing sessions. That rule alone deadlocks if the one
/// invite is missed/declined/timed-out, so this policy adds **bounded retry** for the primary
/// inviter and a **rare late fallback** for the non-inviter (covers a wedged primary). It is
/// pure logic — no timers, no MultipeerConnectivity — so it's unit-testable on any host and
/// mirrors the proven BLE reconnect-cooldown approach (no busy-loop on the radio).
public struct MultipeerRetryPolicy: Sendable {

    /// First retry delay; doubles each attempt.
    public let baseDelay: TimeInterval
    /// Cap on the exponential backoff.
    public let maxDelay: TimeInterval
    /// The non-inviter only steps in this long after first discovering the peer.
    public let nonInviterFallbackAfter: TimeInterval

    public init(baseDelay: TimeInterval = 2,
                maxDelay: TimeInterval = 16,
                nonInviterFallbackAfter: TimeInterval = 20) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.nonInviterFallbackAfter = nonInviterFallbackAfter
    }

    /// Backoff before the Nth invite (0-based): attempt 0 is immediate; thereafter
    /// `baseDelay * 2^(n-1)`, capped at `maxDelay`. Deterministic (jitter, if any, is the
    /// caller's concern) so it can be asserted exactly in tests.
    public func backoff(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let raw = baseDelay * pow(2, Double(attempt - 1))
        return min(raw, maxDelay)
    }

    /// Whether THIS device should invite the given peer right now.
    ///
    /// - Parameters:
    ///   - isPrimaryInviter: `true` when `localPeer.displayName > peer.displayName`.
    ///   - attempts: invites already sent to this peer (0 = none yet).
    ///   - lastInviteAt: when we last invited, or `nil` if never.
    ///   - firstSeen: when we first discovered this peer.
    ///   - now: current time.
    public func shouldInvite(isPrimaryInviter: Bool,
                             attempts: Int,
                             lastInviteAt: Date?,
                             firstSeen: Date,
                             now: Date) -> Bool {
        guard let last = lastInviteAt else {
            // Never invited: the primary goes immediately; the non-inviter waits out the
            // fallback window first (so it only steps in if the primary clearly failed).
            return isPrimaryInviter || now.timeIntervalSince(firstSeen) >= nonInviterFallbackAfter
        }
        if !isPrimaryInviter, now.timeIntervalSince(firstSeen) < nonInviterFallbackAfter {
            return false
        }
        return now.timeIntervalSince(last) >= backoff(forAttempt: attempts)
    }
}
