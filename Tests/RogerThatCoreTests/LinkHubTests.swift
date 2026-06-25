import Testing
import Foundation
@testable import RogerThatCore

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&value) } }
    var current: T { lock.withLock { value } }
}

@Suite("LinkHub")
struct LinkHubTests {

    private func text(_ s: String) -> Data { Data(s.utf8) }
    private func string(_ d: Data) -> String { String(data: d, encoding: .utf8) ?? "" }

    @Test func fansInboundOutToAllPorts() {
        let base = InMemoryLink(id: "A")
        let other = InMemoryLink(id: "B")
        let hub = LinkHub(base: base)
        let p1 = hub.makePort(), p2 = hub.makePort()
        let r1 = Box<[String]>([]), r2 = Box<[String]>([])
        p1.setHandlers(onReceive: { d, _ in r1.mutate { $0.append(self.string(d)) } }, onPeerEvent: { _, _ in })
        p2.setHandlers(onReceive: { d, _ in r2.mutate { $0.append(self.string(d)) } }, onPeerEvent: { _, _ in })
        base.connect(to: other)

        other.broadcast(text("hello"))
        #expect(r1.current == ["hello"])
        #expect(r2.current == ["hello"])
    }

    @Test func portBroadcastReachesBaseTransport() {
        let base = InMemoryLink(id: "A")
        let other = InMemoryLink(id: "B")
        let hub = LinkHub(base: base)
        let port = hub.makePort()
        port.setHandlers(onReceive: { _, _ in }, onPeerEvent: { _, _ in })
        base.connect(to: other)
        let got = Box<[String]>([])
        other.setHandlers(onReceive: { d, _ in got.mutate { $0.append(self.string(d)) } }, onPeerEvent: { _, _ in })

        port.broadcast(text("yo"))
        #expect(got.current == ["yo"])
        #expect(port.peers.contains(PeerHandle("B")))
    }

    @Test func peerEventsFanOut() {
        let base = InMemoryLink(id: "A")
        let other = InMemoryLink(id: "B")
        let hub = LinkHub(base: base)
        let port = hub.makePort()
        let events = Box<[String]>([])
        port.setHandlers(onReceive: { _, _ in }, onPeerEvent: { _, e in events.mutate { $0.append("\(e)") } })

        base.connect(to: other)
        #expect(events.current.contains("connected"))
    }

    @Test func removedPortStopsReceiving() {
        let base = InMemoryLink(id: "A")
        let other = InMemoryLink(id: "B")
        let hub = LinkHub(base: base)
        let p1 = hub.makePort(), p2 = hub.makePort()
        let r1 = Box<[String]>([]), r2 = Box<[String]>([])
        p1.setHandlers(onReceive: { d, _ in r1.mutate { $0.append(self.string(d)) } }, onPeerEvent: { _, _ in })
        p2.setHandlers(onReceive: { d, _ in r2.mutate { $0.append(self.string(d)) } }, onPeerEvent: { _, _ in })
        base.connect(to: other)

        hub.removePort(p1)
        other.broadcast(text("after"))
        #expect(r1.current.isEmpty)
        #expect(r2.current == ["after"])
    }

    /// The real multi-channel proof: two channels' routers share ONE transport via the
    /// hub, and each only delivers its own channel's traffic (cross-channel is filtered).
    @Test func twoChannelsShareOneTransportButStayIsolated() {
        // Two devices, each running two channels (A and B) over a single shared link.
        let baseL = InMemoryLink(id: "L")
        let baseR = InMemoryLink(id: "R")
        baseL.connect(to: baseR)
        let hubL = LinkHub(base: baseL)
        let hubR = LinkHub(base: baseR)

        let chA: UInt32 = 0xAAAA0000
        let chB: UInt32 = 0xBBBB0000

        func router(_ hub: LinkHub, _ hash: UInt32, sender: UInt32) -> FloodRouter {
            let r = FloodRouter(link: hub.makePort(), channelIDHash: hash, senderID: sender)
            r.synchronousDelivery = true
            return r
        }

        let lA = router(hubL, chA, sender: 1)
        let lB = router(hubL, chB, sender: 2)
        let rA = router(hubR, chA, sender: 3)
        let rB = router(hubR, chB, sender: 4)

        let aGot = Box<[String]>([]), bGot = Box<[String]>([])
        rA.setMessageHandler { msg in aGot.mutate { $0.append(String(data: msg.plaintext, encoding: .utf8) ?? "") } }
        rB.setMessageHandler { msg in bGot.mutate { $0.append(String(data: msg.plaintext, encoding: .utf8) ?? "") } }
        lA.setMessageHandler { _ in }
        lB.setMessageHandler { _ in }

        // Send on channel A from the left device; only the right's channel-A router hears it.
        lA.send(text: text("for-A"))
        #expect(aGot.current == ["for-A"])
        #expect(bGot.current.isEmpty)

        // Send on channel B; only channel-B router hears it.
        lB.send(text: text("for-B"))
        #expect(bGot.current == ["for-B"])
        #expect(aGot.current == ["for-A"])   // channel A unchanged
    }
}
