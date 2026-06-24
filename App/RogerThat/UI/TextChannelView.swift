import SwiftUI
import RogerThatCore

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable { case message, system }

    let id = UUID()
    let kind: Kind
    let senderName: String
    let text: String
    let timestamp: Date
    let isLocal: Bool

    init(kind: Kind = .message, senderName: String, text: String, timestamp: Date, isLocal: Bool) {
        self.kind = kind
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.isLocal = isLocal
    }

    /// A centered, light system notice (e.g. "Alice joined").
    static func system(_ text: String, timestamp: Date = Date()) -> ChatMessage {
        ChatMessage(kind: .system, senderName: "", text: text, timestamp: timestamp, isLocal: false)
    }
}

/// Flooded text message list + compose bar, styled after iMessage group chats:
/// system notices, sender grouping for consecutive messages, and swipe-left to
/// reveal per-message timestamps.
struct TextChannelView: View {
    @EnvironmentObject var appState: AppState
    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    /// How far the conversation is dragged left to reveal timestamps (0...revealWidth).
    @State private var reveal: CGFloat = 0

    private let revealWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(appState.messages.enumerated()), id: \.element.id) { index, msg in
                            row(at: index, msg: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(timestampRevealGesture)
                .onChange(of: appState.messages.count) { _, _ in
                    if let last = appState.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($composerFocused)

                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    appState.sendText(text)
                    draft = ""
                    composerFocused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(at index: Int, msg: ChatMessage) -> some View {
        VStack(spacing: 0) {
            if showsTimeSeparator(at: index) {
                TimeSeparator(date: msg.timestamp)
                    .padding(.top, index == 0 ? 0 : 12)
                    .padding(.bottom, 6)
            }

            switch msg.kind {
            case .system:
                SystemNotice(text: msg.text)
                    .padding(.vertical, 4)
            case .message:
                MessageRow(message: msg,
                           isFirstOfRun: isFirstOfRun(at: index),
                           reveal: reveal,
                           revealWidth: revealWidth)
                    .padding(.top, isFirstOfRun(at: index) ? 6 : 1)
            }
        }
    }

    // MARK: - Grouping helpers

    /// First message of a visual run (sender changed, prior was a system notice,
    /// or a long pause). Controls whether the sender name is shown.
    private func isFirstOfRun(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let cur = appState.messages[index]
        let prev = appState.messages[index - 1]
        if prev.kind == .system { return true }
        if prev.senderName != cur.senderName || prev.isLocal != cur.isLocal { return true }
        if cur.timestamp.timeIntervalSince(prev.timestamp) > 5 * 60 { return true }
        return false
    }

    /// Centered time separator before the first message and after long gaps.
    private func showsTimeSeparator(at index: Int) -> Bool {
        let cur = appState.messages[index]
        guard cur.kind == .message else { return false }
        guard index > 0 else { return true }
        let prev = appState.messages[index - 1]
        return cur.timestamp.timeIntervalSince(prev.timestamp) > 15 * 60
    }

    // MARK: - Swipe-to-reveal gesture

    private var timestampRevealGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Only react to leftward, horizontally-dominant drags so vertical
                // scrolling keeps working.
                if value.translation.width < 0,
                   abs(value.translation.width) > abs(value.translation.height) {
                    reveal = min(revealWidth, -value.translation.width)
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { reveal = 0 }
            }
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ChatMessage
    let isFirstOfRun: Bool
    let reveal: CGFloat
    let revealWidth: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            // Timestamp parked off the right edge; slides in as the row is dragged left.
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: revealWidth, alignment: .leading)
                .offset(x: revealWidth - reveal)
                .opacity(Double(reveal / revealWidth))

            bubble
                .offset(x: -reveal)
        }
        .frame(maxWidth: .infinity, alignment: message.isLocal ? .trailing : .leading)
        .clipped()
    }

    private var bubble: some View {
        HStack {
            if message.isLocal { Spacer(minLength: 48) }

            VStack(alignment: message.isLocal ? .trailing : .leading, spacing: 2) {
                if !message.isLocal && isFirstOfRun {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isLocal ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(message.isLocal ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if !message.isLocal { Spacer(minLength: 48) }
        }
    }
}

// MARK: - System notice

private struct SystemNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Time separator

private struct TimeSeparator: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var label: String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return time }
        if cal.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
