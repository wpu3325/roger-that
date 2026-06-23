import Foundation
import AVFoundation
import RogerThatCore

/// 20 ms at 16 kHz mono = 320 samples.
private let frameSamples = 320
private let sampleRate: Double = 16_000

/// Manages AVAudioEngine for PTT capture and playback.
///
/// Default codec: RawPCMCodec (PCM passthrough).
/// HUMAN: Replace with OpusCodec once libopus is integrated.
final class AudioEngineIO {

    private let engine = AVAudioEngine()
    private let codec: any AudioCodec = RawPCMCodec()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: true
    )!

    let jitterBuffer = JitterBuffer(capacity: 3)
    var onEncodedFrame: ((Data) -> Void)?

    // MARK: - Capture (TX)

    func startCapture() throws {
        try configureAudioSession()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        let converter = AVAudioConverter(from: inputFormat, to: format)

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(frameSamples), format: inputFormat) {
            [weak self] buffer, _ in
            guard let self, let converter else { return }
            self.encodeAndSend(buffer: buffer, converter: converter)
        }

        try engine.start()
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        deactivateAudioSession()
    }

    // MARK: - Playback (RX)

    func enqueueFrame(_ data: Data) {
        jitterBuffer.enqueue(data)
    }

    // MARK: - Private

    private func encodeAndSend(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: AVAudioFrameCount(frameSamples)) else { return }
        var error: NSError?
        var didConvert = false
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, let int16Ptr = outBuffer.int16ChannelData else { return }
        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let pcm = Data(bytes: int16Ptr[0], count: byteCount)
        if let encoded = try? codec.encode(pcm: pcm) {
            onEncodedFrame?(encoded)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
