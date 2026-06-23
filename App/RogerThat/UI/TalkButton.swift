import SwiftUI
import RogerThatCore

/// Large push-and-hold PTT button; also supports tap-to-toggle accessibility mode.
struct TalkButton: View {
    @EnvironmentObject var appState: AppState
    @State private var isToggleMode = false
    @State private var toggled = false

    private var isTalking: Bool {
        if case .talkingLocal = appState.floorState { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            // Accessibility toggle
            Toggle("Tap-to-toggle mode", isOn: $isToggleMode)
                .font(.caption)
                .tint(.accentColor)

            if isToggleMode {
                tapToggleButton
            } else {
                holdButton
            }

            // TODO: Map hardware volume buttons to PTT.
            // The AVAudioSession route-change approach cannot be done without
            // a physical device and an active audio session.
        }
    }

    // MARK: - Press-and-hold

    private var holdButton: some View {
        Circle()
            .fill(isTalking ? Color.green : Color.accentColor)
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: isTalking ? "waveform" : "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isTalking ? 1.12 : 1.0)
            .animation(.spring(duration: 0.15), value: isTalking)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isTalking { appState.pttController?.startTalking() }
                    }
                    .onEnded { _ in
                        appState.pttController?.stopTalking()
                    }
            )
            .accessibilityLabel(isTalking ? "Release to stop" : "Hold to talk")
    }

    // MARK: - Tap-to-toggle

    private var tapToggleButton: some View {
        Button {
            if toggled {
                appState.pttController?.stopTalking()
            } else {
                appState.pttController?.startTalking()
            }
            toggled.toggle()
        } label: {
            Circle()
                .fill(toggled ? Color.green : Color.accentColor)
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: toggled ? "waveform" : "mic.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
        }
        .accessibilityLabel(toggled ? "Tap to stop talking" : "Tap to start talking")
    }
}
