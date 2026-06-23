import Foundation

/// Optimistic PTT floor state: last-start-wins on collision.
public enum FloorState: Sendable, Equatable {
    case idle
    case talkingLocal
    case talkingRemote(speakerID: UInt32, displayName: String)
}

/// Manages who holds the PTT floor.
public final class PTTFloor: @unchecked Sendable {

    private let lock = NSLock()
    private var _state: FloorState = .idle
    private var onStateChange: (@Sendable (FloorState) -> Void)?

    public var state: FloorState {
        lock.withLock { _state }
    }

    public func setStateChangeHandler(_ handler: @escaping @Sendable (FloorState) -> Void) {
        lock.withLock { onStateChange = handler }
    }

    public func localTalkStart() {
        updateState(.talkingLocal)
    }

    public func localTalkEnd() {
        lock.withLock {
            if case .talkingLocal = _state { _state = .idle }
        }
        notify()
    }

    public func remoteTalkStart(speakerID: UInt32, displayName: String) {
        updateState(.talkingRemote(speakerID: speakerID, displayName: displayName))
    }

    public func remoteTalkEnd(speakerID: UInt32) {
        lock.withLock {
            if case .talkingRemote(let id, _) = _state, id == speakerID {
                _state = .idle
            }
        }
        notify()
    }

    private func updateState(_ newState: FloorState) {
        lock.withLock { _state = newState }
        notify()
    }

    private func notify() {
        let s = lock.withLock { _state }
        let handler = lock.withLock { onStateChange }
        handler?(s)
    }
}
