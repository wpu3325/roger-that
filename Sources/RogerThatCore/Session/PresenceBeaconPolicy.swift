import Foundation

/// Decides, per timer tick, whether to actually emit a presence beacon.
///
/// Beacons are the steady-state radio cost: with no one around there's nothing to announce
/// to, so we back off to one beacon every `aloneEveryNTicks` ticks. The instant a peer
/// connects we beacon every tick again (and `SessionManager` also fires an immediate beacon
/// on connect, so back-off never delays first appearance). Pure logic so it's unit-testable.
public struct PresenceBeaconPolicy: Sendable {

    /// When alone (no connected peers), beacon once per this many ticks.
    public let aloneEveryNTicks: Int

    public init(aloneEveryNTicks: Int = 3) {
        self.aloneEveryNTicks = max(1, aloneEveryNTicks)
    }

    /// `tick` is a monotonically increasing fire count (0-based).
    public func shouldBeacon(tick: Int, hasPeers: Bool) -> Bool {
        if hasPeers { return true }
        return tick % aloneEveryNTicks == 0
    }
}
