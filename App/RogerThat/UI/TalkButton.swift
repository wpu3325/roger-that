import SwiftUI
import RogerThatCore

/// Large push-and-hold PTT button; also supports tap-to-toggle mode.
/// isToggleMode is persisted so the chosen mode (hold vs tap-to-toggle) survives relaunch.
struct TalkButton: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("rogerthat.pttToggleMode") private var isToggleMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTalking: Bool {
        if case .talkingLocal = appState.floorState { return true }
        return false
    }

    /// A peer holds the floor — block local TX (half-duplex) and dim the button.
    private var isRemoteTalking: Bool {
        if case .talkingRemote = appState.floorState { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            Toggle("Tap-to-toggle mode", isOn: $isToggleMode)
                .font(.caption)
                .tint(.accentColor)

            if isToggleMode {
                tapToggleButton
            } else {
                holdButton
            }
        }
        .onChange(of: isTalking) { _, talking in
            let haptic = UIImpactFeedbackGenerator(style: talking ? .medium : .light)
            haptic.impactOccurred()
        }
    }

    // MARK: - Shared button face

    private func buttonFace(size: CGFloat = 120) -> some View {
        Circle()
            .fill(isTalking ? Color.green : Color.accentColor)
            .frame(width: size, height: size)
            .overlay {
                if isTalking {
                    VoiceWaveformView(level: CGFloat(appState.voiceLevel),
                                      color: .white,
                                      maxBarHeight: size * 0.42,
                                      barWidth: size * 0.05)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: size * 0.37))
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(isTalking && !reduceMotion ? 1.1 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: isTalking)
    }

    // MARK: - Press-and-hold

    private var holdButton: some View {
        buttonFace()
            .opacity(isRemoteTalking ? 0.4 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isTalking && appState.canStartTalking {
                            appState.pttController?.startTalking()
                        }
                    }
                    .onEnded { _ in
                        appState.pttController?.stopTalking()
                    }
            )
            .allowsHitTesting(!isRemoteTalking)
            .accessibilityLabel(isTalking ? "Release to stop" : "Hold to talk")
    }

    // MARK: - Tap-to-toggle

    private var tapToggleButton: some View {
        Button {
            if isTalking {
                appState.pttController?.stopTalking()
            } else if appState.canStartTalking {
                appState.pttController?.startTalking()
            }
        } label: {
            buttonFace()
                .opacity(isRemoteTalking ? 0.4 : 1)
        }
        .disabled(isRemoteTalking)
        .accessibilityLabel(isTalking ? "Tap to stop talking" : "Tap to start talking")
    }
}
