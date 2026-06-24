import Foundation
@preconcurrency import AVFoundation
import RogerThatCore

/// 20 ms at 16 kHz mono = 320 samples.
private let frameSamples = 320
private let sampleRate: Double = 16_000

/// Manages AVAudioEngine for PTT capture and playback.
///
/// The engine + player node run for the whole time you're in a channel (started via
/// `startSession`), so incoming voice plays the moment a peer transmits — you do NOT
/// have to be talking to hear others. Capture (the mic tap) is installed only while
/// PTT is held.
///
/// Default codec: RawPCMCodec (PCM passthrough).
/// HUMAN: Replace with OpusCodec once libopus is integrated.
final class AudioEngineIO {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let codec: any RogerThatCore.AudioCodec = RawPCMCodec()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: true
    )!

    var onEncodedFrame: ((Data) -> Void)?
    /// Normalized 0...1 mic level while transmitting (drives the local waveform).
    var onInputLevel: ((Float) -> Void)?
    /// Normalized 0...1 level of incoming audio (drives the remote waveform).
    var onOutputLevel: ((Float) -> Void)?

    private var captureConverter: AVAudioConverter?
    private var sessionActive = false

    // MARK: - Session lifecycle (whole channel)

    /// Bring up the audio session + player node so we can hear peers immediately.
    func startSession() {
        guard !sessionActive else { return }
        do {
            try configureAudioSession()
            if !engine.attachedNodes.contains(player) {
                engine.attach(player)
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            _ = engine.inputNode            // pull the input node into the graph
            engine.prepare()
            try engine.start()
            player.play()
            sessionActive = true
        } catch {
            sessionActive = false
        }
    }

    func stopSession() {
        engine.inputNode.removeTap(onBus: 0)
        captureConverter = nil
        player.stop()
        engine.stop()
        if engine.attachedNodes.contains(player) {
            engine.detach(player)
        }
        deactivateAudioSession()
        sessionActive = false
    }

    // MARK: - Capture (TX) — half-duplex while PTT is held

    func startCapture() throws {
        if !sessionActive { startSession() }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inputFormat, to: format)
        captureConverter = converter

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(frameSamples), format: inputFormat) {
            [weak self] buffer, _ in
            guard let self, let converter = self.captureConverter else { return }
            self.encodeAndSend(buffer: buffer, converter: converter)
        }

        if !engine.isRunning { try engine.start() }
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        captureConverter = nil
        // Engine + player keep running so we can still hear others.
    }

    // MARK: - Playback (RX)

    /// Decode an incoming compressed frame and schedule it for playback.
    func playEncoded(_ encoded: Data) {
        guard let pcm = try? codec.decode(frame: encoded),
              let buffer = makeBuffer(from: pcm) else { return }
        if !sessionActive { startSession() }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
        onOutputLevel?(Self.rmsLevel(pcm))
    }

    // MARK: - Private

    private func makeBuffer(from pcm: Data) -> AVAudioPCMBuffer? {
        let frames = UInt32(pcm.count / MemoryLayout<Int16>.size)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channel = buffer.int16ChannelData else { return nil }
        pcm.withUnsafeBytes { raw in
            if let base = raw.bindMemory(to: Int16.self).baseAddress {
                channel[0].update(from: base, count: Int(frames))
            }
        }
        return buffer
    }

    private func encodeAndSend(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: AVAudioFrameCount(frameSamples)) else { return }
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, let int16Ptr = outBuffer.int16ChannelData else { return }
        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let pcm = Data(bytes: int16Ptr[0], count: byteCount)
        onInputLevel?(Self.rmsLevel(pcm))
        if let encoded = try? codec.encode(pcm: pcm) {
            onEncodedFrame?(encoded)
        }
    }

    /// RMS amplitude of a 16-bit PCM buffer, normalized to roughly 0...1 for speech.
    private static func rmsLevel(_ pcm: Data) -> Float {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0 else { return 0 }
        return pcm.withUnsafeBytes { raw -> Float in
            let samples = raw.bindMemory(to: Int16.self)
            var sum: Float = 0
            for i in 0..<count {
                let s = Float(samples[i]) / 32768.0
                sum += s * s
            }
            let rms = (sum / Float(count)).squareRoot()
            return min(1, rms * 8)   // gain up; speech RMS is small
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        // voiceChat mode otherwise routes to the quiet earpiece; force the loudspeaker
        // for a walkie-talkie feel (no-op when a Bluetooth headset is connected).
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
