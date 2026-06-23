/// Wire protocol message types.
public enum MessageType: UInt8, Sendable {
    case presence   = 0
    case text       = 1
    case voiceFrame = 2
    case talkStart  = 3
    case talkEnd    = 4
}
