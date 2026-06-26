import Testing
@testable import RogerThatCore

@Suite("PresenceBeaconPolicy")
struct PresenceBeaconPolicyTests {

    @Test func beaconsEveryTickWhenPeersPresent() {
        let policy = PresenceBeaconPolicy(aloneEveryNTicks: 3)
        for tick in 0..<10 {
            #expect(policy.shouldBeacon(tick: tick, hasPeers: true))
        }
    }

    @Test func backsOffWhenAlone() {
        let policy = PresenceBeaconPolicy(aloneEveryNTicks: 3)
        #expect(policy.shouldBeacon(tick: 0, hasPeers: false))
        #expect(!policy.shouldBeacon(tick: 1, hasPeers: false))
        #expect(!policy.shouldBeacon(tick: 2, hasPeers: false))
        #expect(policy.shouldBeacon(tick: 3, hasPeers: false))
        #expect(policy.shouldBeacon(tick: 6, hasPeers: false))
    }

    @Test func clampsIntervalToAtLeastOne() {
        // A zero/negative interval would divide-by-zero; it must clamp to 1 (every tick).
        let policy = PresenceBeaconPolicy(aloneEveryNTicks: 0)
        #expect(policy.aloneEveryNTicks == 1)
        #expect(policy.shouldBeacon(tick: 5, hasPeers: false))
    }
}
