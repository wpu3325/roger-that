import Foundation

/// Simple receive-side jitter buffer for voice frames.
///
/// Holds 2–4 frames (configurable). Frames are enqueued on the receive thread
/// and dequeued on the audio render thread.
final class JitterBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var frames: [Data] = []
    let capacity: Int

    init(capacity: Int = 3) {
        self.capacity = capacity
    }

    func enqueue(_ frame: Data) {
        lock.withLock {
            frames.append(frame)
            if frames.count > capacity {
                frames.removeFirst()  // drop oldest on overflow
            }
        }
    }

    func dequeue() -> Data? {
        lock.withLock {
            frames.isEmpty ? nil : frames.removeFirst()
        }
    }

    var isEmpty: Bool {
        lock.withLock { frames.isEmpty }
    }
}
