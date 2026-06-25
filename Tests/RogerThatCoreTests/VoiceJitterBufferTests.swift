import Testing
import Foundation
@testable import RogerThatCore

@Suite("VoiceJitterBuffer")
struct VoiceJitterBufferTests {

    private func frame(_ sid: UInt32, _ seq: UInt32, _ p: String) -> VoiceFrame {
        VoiceFrame(sessionID: sid, seq: seq, payload: Data(p.utf8))
    }

    /// Map outputs to a comparable string list ("<conceal>" for concealment).
    private func plays(_ out: [JitterOutput]) -> [String] {
        out.map { output in
            switch output {
            case .play(let p): return String(data: p, encoding: .utf8) ?? "<?>"
            case .conceal:     return "<conceal>"
            }
        }
    }

    // MARK: - Priming

    @Test func primesBeforeFirstEmit() {
        let jb = VoiceJitterBuffer(startDepth: 3, maxDepth: 12, reorderWindow: 2)
        #expect(plays(jb.enqueue(frame(1, 0, "a"))).isEmpty)
        #expect(plays(jb.enqueue(frame(1, 1, "b"))).isEmpty)
        #expect(plays(jb.enqueue(frame(1, 2, "c"))) == ["a", "b", "c"])
        // Once primed, subsequent in-order frames play immediately.
        #expect(plays(jb.enqueue(frame(1, 3, "d"))) == ["d"])
    }

    // MARK: - Reordering

    @Test func reordersWithinWindow() {
        let jb = VoiceJitterBuffer(startDepth: 1, maxDepth: 12, reorderWindow: 2)
        #expect(plays(jb.enqueue(frame(1, 0, "a"))) == ["a"])
        #expect(plays(jb.enqueue(frame(1, 2, "c"))).isEmpty)        // gap at 1 — hold
        #expect(plays(jb.enqueue(frame(1, 1, "b"))) == ["b", "c"])  // 1 arrives — drain in order
    }

    // MARK: - Loss concealment

    @Test func concealsLostFrame() {
        let jb = VoiceJitterBuffer(startDepth: 1, maxDepth: 12, reorderWindow: 2)
        #expect(plays(jb.enqueue(frame(1, 0, "a"))) == ["a"])
        #expect(plays(jb.enqueue(frame(1, 2, "c"))).isEmpty)        // 1 missing, only 1 frame ahead
        // 3 arrives: newest (3) >= nextSeq(1) + window(2) → declare 1 lost, conceal, then c, d.
        #expect(plays(jb.enqueue(frame(1, 3, "d"))) == ["<conceal>", "c", "d"])
    }

    // MARK: - Dedup / late

    @Test func dropsDuplicate() {
        let jb = VoiceJitterBuffer(startDepth: 1, reorderWindow: 2)
        _ = jb.enqueue(frame(1, 0, "a"))
        #expect(plays(jb.enqueue(frame(1, 1, "b"))) == ["b"])
        #expect(plays(jb.enqueue(frame(1, 1, "b-dup"))).isEmpty)
    }

    @Test func dropsFrameAfterItsSlotPlayed() {
        let jb = VoiceJitterBuffer(startDepth: 1, reorderWindow: 2)
        _ = jb.enqueue(frame(1, 0, "a"))
        _ = jb.enqueue(frame(1, 1, "b"))
        #expect(plays(jb.enqueue(frame(1, 0, "a-late"))).isEmpty)
    }

    // MARK: - New burst

    @Test func newSessionResetsAndReprimes() {
        let jb = VoiceJitterBuffer(startDepth: 2, reorderWindow: 2)
        _ = jb.enqueue(frame(1, 0, "a"))
        #expect(plays(jb.enqueue(frame(1, 1, "b"))) == ["a", "b"])
        // New sessionID starting from an arbitrary seq base must re-prime.
        #expect(plays(jb.enqueue(frame(2, 5, "x"))).isEmpty)
        #expect(plays(jb.enqueue(frame(2, 6, "y"))) == ["x", "y"])
    }

    // MARK: - Overflow

    @Test func fastForwardsWhenFarBehind() {
        // reorderWindow huge so concealment never triggers; maxDepth must bound latency.
        let jb = VoiceJitterBuffer(startDepth: 1, maxDepth: 3, reorderWindow: 100)
        #expect(plays(jb.enqueue(frame(1, 0, "a"))) == ["a"])       // nextSeq now 1
        _ = jb.enqueue(frame(1, 5, "f5"))
        _ = jb.enqueue(frame(1, 6, "f6"))
        _ = jb.enqueue(frame(1, 7, "f7"))
        // pending {5,6,7,8} exceeds maxDepth(3) → fast-forward to oldest held (5).
        #expect(plays(jb.enqueue(frame(1, 8, "f8"))) == ["f5", "f6", "f7", "f8"])
    }

    @Test func resetForcesReprime() {
        let jb = VoiceJitterBuffer(startDepth: 2, reorderWindow: 2)
        _ = jb.enqueue(frame(1, 0, "a"))
        _ = jb.enqueue(frame(1, 1, "b"))
        jb.reset()
        #expect(plays(jb.enqueue(frame(1, 2, "c"))).isEmpty)        // must re-prime after reset
    }
}
