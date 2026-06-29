import Testing
@testable import RogerThatCore

@Suite("VoiceLinkStatus")
struct VoiceLinkStatusTests {

    @Test func connectedWinsOverEverything() {
        #expect(VoiceLinkStatus.evaluate(connected: 2, connecting: 3, elapsed: 99,
                                         noPeerThreshold: 8) == .connected(peers: 2))
    }

    @Test func connectingWhenHandshaking() {
        #expect(VoiceLinkStatus.evaluate(connected: 0, connecting: 1, elapsed: 99,
                                         noPeerThreshold: 8) == .connecting)
    }

    @Test func connectingBeforeThresholdWithNobody() {
        #expect(VoiceLinkStatus.evaluate(connected: 0, connecting: 0, elapsed: 3,
                                         noPeerThreshold: 8) == .connecting)
    }

    @Test func noPeersAfterThreshold() {
        #expect(VoiceLinkStatus.evaluate(connected: 0, connecting: 0, elapsed: 8,
                                         noPeerThreshold: 8) == .noPeers)
    }

    @Test func unavailableReasonsAreDistinct() {
        #expect(VoiceLinkStatus.unavailable(.localNetworkDenied)
                != VoiceLinkStatus.unavailable(.microphoneDenied))
    }
}
