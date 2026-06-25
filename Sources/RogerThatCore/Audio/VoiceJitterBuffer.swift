import Foundation

/// One received voice frame: the talk-burst it belongs to, its position in that burst,
/// and the (still-encoded) payload.
public struct VoiceFrame: Sendable, Equatable {
    public let sessionID: UInt32
    public let seq: UInt32
    public let payload: Data

    public init(sessionID: UInt32, seq: UInt32, payload: Data) {
        self.sessionID = sessionID
        self.seq = seq
        self.payload = payload
    }
}

/// What the playout side should do next, in order.
public enum JitterOutput: Sendable, Equatable {
    /// Schedule this encoded payload for playback.
    case play(Data)
    /// The frame at this position was lost — synthesize concealment (PLC) so the
    /// cadence stays intact instead of leaving an audible gap.
    case conceal
}

/// Receive-side jitter buffer for push-to-talk voice.
///
/// Voice frames arrive over an *unreliable* transport: they can be reordered, duplicated,
/// or dropped, and they bunch up with network jitter. Scheduling each one the instant it
/// lands makes the audio choppy. This buffer absorbs that:
///
/// - **Reorders** by `seq` within a small window so slightly-late frames still play in order.
/// - **Drops** duplicates and frames that arrive after their slot already played.
/// - **Conceals** losses: once enough later frames have arrived that a hole can't just be
///   reordering, it emits `.conceal` and moves on rather than stalling.
/// - **Primes** a short cushion (`startDepth` frames) before the first emit so a burst opens
///   smoothly, and **fast-forwards** if it ever falls more than `maxDepth` behind (keeps
///   end-to-end latency bounded after a stall).
/// - **Resets** automatically when a new talk burst (new `sessionID`) begins.
///
/// Pure logic, no platform/audio dependencies — unit-tested in Core. The audio layer turns
/// `.play`/`.conceal` into scheduled buffers.
///
/// Not thread-safe: drive it from a single consumer (the app feeds it on the main actor).
public final class VoiceJitterBuffer {

    /// Frames to buffer before the first emit (playout cushion). ~3 × 20 ms = 60 ms.
    public let startDepth: Int
    /// If buffered frames exceed this, we've fallen behind — fast-forward to the oldest
    /// held frame to claw back latency. ~12 × 20 ms = 240 ms.
    public let maxDepth: Int
    /// How many frames must arrive *beyond* a hole before we declare it lost (vs. reordered).
    public let reorderWindow: UInt32

    private var currentSession: UInt32?
    private var nextSeq: UInt32 = 0
    private var pending: [UInt32: Data] = [:]
    private var primed = false

    public init(startDepth: Int = 3, maxDepth: Int = 12, reorderWindow: UInt32 = 2) {
        self.startDepth = max(1, startDepth)
        self.maxDepth = max(startDepth, maxDepth)
        self.reorderWindow = max(1, reorderWindow)
    }

    /// Feed one received frame; returns zero or more ordered playout actions.
    public func enqueue(_ frame: VoiceFrame) -> [JitterOutput] {
        if frame.sessionID != currentSession {
            // New talk burst — start fresh from this frame's position.
            currentSession = frame.sessionID
            nextSeq = frame.seq
            pending = [frame.seq: frame.payload]
            primed = false
            return drain()
        }

        if frame.seq < nextSeq { return [] }          // its slot already played — too late
        if pending[frame.seq] != nil { return [] }    // duplicate
        pending[frame.seq] = frame.payload
        return drain()
    }

    /// Forget the current burst (call on talk-end / leaving the channel) so the next frame
    /// re-primes cleanly instead of trying to bridge a long silence.
    public func reset() {
        currentSession = nil
        nextSeq = 0
        pending.removeAll()
        primed = false
    }

    // MARK: - Private

    private func drain() -> [JitterOutput] {
        if !primed {
            guard pending.count >= startDepth else { return [] }
            primed = true
        }

        // Fallen too far behind (e.g. a batch landed after a stall) — skip ahead to the
        // oldest held frame so we don't accumulate unbounded latency.
        if pending.count > maxDepth, let oldest = pending.keys.min() {
            nextSeq = oldest
        }

        var out: [JitterOutput] = []
        while true {
            if let payload = pending.removeValue(forKey: nextSeq) {
                out.append(.play(payload))
                nextSeq &+= 1
                continue
            }
            // Hole at nextSeq. If frames have piled up well past it, the missing one isn't
            // just reordered — it's lost. Conceal and advance. Otherwise wait for it.
            if let newest = pending.keys.max(), newest >= nextSeq &+ reorderWindow {
                out.append(.conceal)
                nextSeq &+= 1
                continue
            }
            break
        }
        return out
    }
}
