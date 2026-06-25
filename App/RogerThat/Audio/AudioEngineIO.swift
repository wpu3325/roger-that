import Foundation
import QuartzCore
@preconcurrency import AVFoundation
import RogerThatCore

/// 20 ms at 16 kHz mono = 320 samples = 640 bytes.
private let frameSamples = 320
private let frameBytes = frameSamples * MemoryLayout<Int16>.size
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
    /// Leftover converted PCM that didn't fill a whole 20 ms frame; prepended next callback
    /// so every emitted frame is exactly `frameBytes` (consistent frames = crisp playback).
    private var txAccumulator = Data()
    private var sessionActive = false

    // MARK: - Playback jitter buffer

    /// Frames are scheduled the instant they arrive only once a small lead is built up;
    /// otherwise network jitter drains the player node between frames and the audio
    /// breaks up. We prime `jitterPrimeFrames` (~60 ms) before starting, and re-prime
    /// after any gap so each new talk burst rebuilds its cushion.
    private var jitterPending: [AVAudioPCMBuffer] = []
    private var jitterPrimed = false
    private var lastFrameTime: CFTimeInterval = 0
    private let jitterPrimeFrames = 3
    private let jitterGapSeconds: CFTimeInterval = 0.4

    private var routeObserver: NSObjectProtocol?

    // MARK: - Session lifecycle (whole channel)

    /// Bring up the audio session + player node so we can hear peers immediately.
    func startSession() {
        guard !sessionActive else { return }
        do {
            try configureAudioSession()
            observeRouteChanges()
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
        txAccumulator.removeAll()
        resetPlayback()
        player.stop()
        engine.stop()
        if engine.attachedNodes.contains(player) {
            engine.detach(player)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        deactivateAudioSession()
        sessionActive = false
    }

    // MARK: - Capture (TX) — half-duplex while PTT is held

    func startCapture() throws {
        if !sessionActive { startSession() }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        captureConverter = AVAudioConverter(from: inputFormat, to: format)
        txAccumulator.removeAll()

        // A larger tap buffer yields stable callbacks; we re-chunk into exact 20 ms frames.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self, let converter = self.captureConverter else { return }
            self.encodeAndSend(buffer: buffer, converter: converter)
        }

        if !engine.isRunning { try engine.start() }
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        captureConverter = nil
        txAccumulator.removeAll()
        // Engine + player keep running so we can still hear others.
    }

    // MARK: - Playback (RX)

    /// Decode an incoming compressed frame and schedule it for playback.
    func playEncoded(_ encoded: Data) {
        guard let pcm = try? codec.decode(frame: encoded),
              let buffer = makeBuffer(from: pcm) else { return }
        if !sessionActive { startSession() }
        onOutputLevel?(Self.rmsLevel(pcm))

        let now = CACurrentMediaTime()
        if now - lastFrameTime > jitterGapSeconds { resetPlayback() }   // new burst → re-prime
        lastFrameTime = now

        if jitterPrimed {
            schedule(buffer)
            return
        }
        // Building the initial cushion: hold frames until we have a lead, then release.
        jitterPending.append(buffer)
        if jitterPending.count >= jitterPrimeFrames {
            jitterPrimed = true
            if !player.isPlaying { player.play() }
            for pending in jitterPending { schedule(pending) }
            jitterPending.removeAll()
        }
    }

    /// Drop the jitter cushion so the next frame starts a fresh burst.
    private func resetPlayback() {
        jitterPending.removeAll()
        jitterPrimed = false
    }

    // MARK: - Private

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

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
        // Size the output by the sample-rate ratio (e.g. 48 kHz → 16 kHz is 3:1).
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard capacity > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        // Feed the source buffer exactly once; signal "no more" on any re-request so the
        // converter doesn't double-consume the same samples (which garbles the audio).
        var fed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, outBuffer.frameLength > 0, let int16Ptr = outBuffer.int16ChannelData else { return }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        txAccumulator.append(Data(bytes: int16Ptr[0], count: byteCount))

        // Emit only whole 20 ms frames; keep any remainder for the next callback.
        while txAccumulator.count >= frameBytes {
            let frame = txAccumulator.prefix(frameBytes)
            txAccumulator.removeFirst(frameBytes)
            let pcm = Data(frame)
            onInputLevel?(Self.rmsLevel(pcm))
            if let encoded = try? codec.encode(pcm: pcm) {
                onEncodedFrame?(encoded)
            }
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
        // `.default` mode + `.defaultToSpeaker` plays out the loud bottom speaker (a
        // walkie-talkie should be heard without raising the phone to your ear). PTT is
        // half-duplex — we never capture and play at the same time — so we skip
        // `.voiceChat`'s aggressive processing, which both routes to the quiet earpiece
        // and pumps/gates the signal.
        try session.setCategory(.playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
    }

    /// iOS can yank the route back to the earpiece on interruptions/category nudges.
    /// Re-assert the loudspeaker, but only when we're actually stuck on the built-in
    /// receiver — never steal the route from plugged-in headphones or Bluetooth.
    private func observeRouteChanges() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let session = AVAudioSession.sharedInstance()
            let onReceiver = session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
            if onReceiver { try? session.overrideOutputAudioPort(.speaker) }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
