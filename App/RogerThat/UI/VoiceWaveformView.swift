import SwiftUI

/// Animated audio-level waveform (like Voice Memos): bars rise and fall with `level`.
struct VoiceWaveformView: View {
    /// Normalized 0...1 audio amplitude.
    var level: CGFloat
    var color: Color = .white
    var barCount: Int = 5
    var maxBarHeight: CGFloat = 40
    var barWidth: CGFloat = 5

    // Per-bar weighting so the middle bars peak higher than the edges.
    private let weights: [CGFloat] = [0.45, 0.75, 1.0, 0.75, 0.45]

    var body: some View {
        HStack(spacing: barWidth * 0.7) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: height(for: index))
            }
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: level)
        .accessibilityHidden(true)   // decorative; the floor banner text conveys the state
    }

    private func height(for index: Int) -> CGFloat {
        let minHeight = barWidth
        let weight = weights[index % weights.count]
        return minHeight + (maxBarHeight - minHeight) * min(1, max(0, level)) * weight
    }
}
