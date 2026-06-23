import Testing
import Foundation
@testable import RogerThatCore

// MARK: - Thread-safe counter

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int: Int] = [:]

    func increment(_ index: Int) {
        lock.withLock { counts[index, default: 0] += 1 }
    }

    func value(at index: Int) -> Int? {
        lock.withLock { counts[index] }
    }

    func snapshot() -> [Int: Int] {
        lock.withLock { counts }
    }
}

// MARK: - Topology builders

private func buildNodes(
    count: Int,
    hash: UInt32,
    edges: [(Int, Int)]
) -> ([InMemoryLink], [FloodRouter]) {
    let links = (0..<count).map { InMemoryLink(id: "\($0)") }
    let routers = links.map { link -> FloodRouter in
        let r = FloodRouter(
            link: link,
            channelIDHash: hash,
            senderID: UInt32(truncatingIfNeeded: link.handle.id.hashValue)
        )
        r.synchronousDelivery = true
        return r
    }
    for (a, b) in edges { links[a].connect(to: links[b]) }
    return (links, routers)
}

private func trackDeliveries(_ routers: [FloodRouter]) -> Counter {
    let counter = Counter()
    for (i, r) in routers.enumerated() {
        let idx = i
        r.setMessageHandler { _ in counter.increment(idx) }
    }
    return counter
}

// MARK: - Tests

@Suite("FloodRouter")
struct FloodRouterTests {

    let hash: UInt32 = 0xABCD1234

    // MARK: Line: 0—1—2—3

    @Test func lineDelivery() {
        let (_, routers) = buildNodes(count: 4, hash: hash, edges: [(0,1),(1,2),(2,3)])
        let d = trackDeliveries(routers)
        routers[0].send(text: Data("Hello".utf8))
        #expect(d.value(at: 0) == nil, "originator must not self-deliver")
        #expect(d.value(at: 1) == 1)
        #expect(d.value(at: 2) == 1)
        #expect(d.value(at: 3) == 1)
    }

    // MARK: Ring: 0—1—2—3—0

    @Test func ringDeduplication() {
        let (_, routers) = buildNodes(count: 4, hash: hash, edges: [(0,1),(1,2),(2,3),(3,0)])
        let d = trackDeliveries(routers)
        routers[0].send(text: Data("Ring".utf8))
        #expect(d.value(at: 0) == nil)
        #expect(d.value(at: 1) == 1)
        #expect(d.value(at: 2) == 1)
        #expect(d.value(at: 3) == 1)
    }

    // MARK: Star: 0 hub, 1/2/3 leaves

    @Test func starDelivery() {
        let (_, routers) = buildNodes(count: 4, hash: hash, edges: [(0,1),(0,2),(0,3)])
        let d = trackDeliveries(routers)
        routers[1].send(text: Data("Star".utf8))
        #expect(d.value(at: 1) == nil)
        #expect(d.value(at: 0) == 1)
        #expect(d.value(at: 2) == 1)
        #expect(d.value(at: 3) == 1)
    }

    // MARK: TTL exhaustion in a line of 12

    @Test func ttlExhaustion() {
        let edges = (0..<11).map { ($0, $0+1) }
        let (_, routers) = buildNodes(count: 12, hash: hash, edges: edges)
        let d = trackDeliveries(routers)
        routers[0].send(text: Data("TTL".utf8))
        // TTL=8 → the packet travels 8 relay-hops: nodes 1..9 receive.
        // Node 9 receives (TTL=0) but does not relay → nodes 10..11 never receive.
        for i in 1...9 { #expect(d.value(at: i) == 1, "node \(i) should receive") }
        #expect(d.value(at: 10) == nil)
        #expect(d.value(at: 11) == nil)
    }

    // MARK: Split-horizon: originator never receives own message

    @Test func splitHorizonNoEcho() {
        let (_, routers) = buildNodes(count: 2, hash: hash, edges: [(0,1)])
        let d = trackDeliveries(routers)
        routers[0].send(text: Data("Echo".utf8))
        #expect(d.value(at: 0) == nil)
    }

    // MARK: Disconnected node never receives

    @Test func disconnectedNodeNoDelivery() {
        let (_, routers) = buildNodes(count: 3, hash: hash, edges: [(0,1)])
        let d = trackDeliveries(routers)
        routers[0].send(text: Data("Isolated".utf8))
        #expect(d.value(at: 2) == nil)
    }

    // MARK: Dedup via SeenCache

    @Test func seenCachePreventsDuplicate() {
        let cache = SeenCache()
        #expect(cache.insert(senderID: 1, messageID: 42) == true)
        #expect(cache.insert(senderID: 1, messageID: 42) == false)
        #expect(cache.insert(senderID: 1, messageID: 43) == true)
        #expect(cache.insert(senderID: 2, messageID: 42) == true)
    }

    // MARK: Cross-channel packets are dropped

    @Test func crossChannelDrop() {
        let link0 = InMemoryLink(id: "A")
        let link1 = InMemoryLink(id: "B")
        link0.connect(to: link1)

        let senderRouter = FloodRouter(link: link0, channelIDHash: hash, senderID: 0xAA)
        senderRouter.synchronousDelivery = true

        let wrongRouter = FloodRouter(link: link1, channelIDHash: 0xFFFFFFFF, senderID: 0xBB)
        wrongRouter.synchronousDelivery = true

        let counter = Counter()
        wrongRouter.setMessageHandler { _ in counter.increment(0) }
        senderRouter.send(text: Data("cross".utf8))
        #expect(counter.value(at: 0) == nil)
    }
}
