import Foundation
@preconcurrency import AVFoundation
import RogerThatCore

/// 20 ms at 16 kHz mono = 320 samples = 640 bytes.
private let frameSamples = 320
private let frameBytes = frameSamples * MemoryLayout<Int16>.size
private let sampleRate: Double = 16_000

/// One-shot flag for the `@Sendable` converter input block. The block is invoked
/// synchronously within `convert`, so a single-threaded mutable flag is safe.
private final class FedFlag: @unchecked Sendable {
    var value = false
}

/// Manages AVAudioEngine for PTT capture and playback.
///
/// The engine + player node run for the whole time you're in a channel (started via
/// `startSession`), so incoming voice plays the moment a peer transmits — you do NOT
/// have to be talking to hear others. Capture (the mic tap) is installed only while
/// PTT is held.
///
/// Frame ordering / reordering / loss detection lives upstream in
/// `RogerThatCore.VoiceJitterBuffer`; this class just turns its decisions into scheduled
/// audio: `playEncoded` for a real frame, `playConcealment` to bridge a lost one.
///
/// Default codec: RawPCMCodec (PCM passthrough).
/// HUMAN: Replace with OpusCodec once libopus is integrated (it also supplies real PLC,
/// at which point `playConcealment` can call the decoder's concealment path).
///
/// `@unchecked Sendable` (matching the transports): TX state (`txAccumulator`,
/// `captureConverter`) is touched only on the audio render thread; RX/PLC state
/// (`lastPCM`, `consecutiveConceals`) and the notification observers run on the main
/// queue. The two don't share mutable state, and AVAudioEngine scheduling is internally
/// thread-safe.
final class AudioEngineIO: @unchecked Sendable {

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
    /// Leftover converted PCM that didn't fill a whole 20 ms frame; carried into the next
    /// callback so every emitted frame is exactly `frameBytes` (consistent frames = crisp).
    private var txAccumulator = Data()
    private var sessionActive = false

    /// Last real PCM frame played, reused to conceal a dropped frame (cheap PLC).
    private var lastPCM: Data?
    private var consecutiveConceals = 0

    private var observers: [NSObjectProtocol] = []

    // MARK: - Session lifecycle (whole channel)

    /// Bring up the audio session + player node so we can hear peers immediately.
    func startSession() {
        guard !sessionActive else { return }
        registerObservers()
        do {
            try activateAndStart()
            sessionActive = true
        } catch {
            // Mic may not be granted yet, or another app holds the session. Leave inactive;
            // the next playEncoded/startCapture retries, and the interruption/route observers
            // recover once the system frees the session.
            sessionActive = false
        }
    }

    func stopSession() {
        engine.inputNode.removeTap(onBus: 0)
        captureConverter = nil
        txAccumulator.removeAll()
        lastPCM = nil
        consecutiveConceals = 0
        player.stop()
        engine.stop()
        if engine.attachedNodes.contains(player) {
            engine.detach(player)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        deactivateAudioSession()
        sessionActive = false
    }

    /// Core bring-up shared by initial start and post-interruption recovery.
    private func activateAndStart() throws {
        try configureAudioSession()
        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        _ = engine.inputNode            // pull the input node into the graph
        engine.prepare()
        try engine.start()
        player.play()
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

    /// Decode an incoming frame and schedule it. Frames arrive here already ordered by the
    /// upstream jitter buffer, so we schedule immediately — the playout cushion is the
    /// buffer's prime depth, not a delay here.
    func playEncoded(_ encoded: Data) {
        guard let pcm = try? codec.decode(frame: encoded),
              let buffer = makeBuffer(from: pcm) else { return }
        if !sessionActive { startSession() }
        if !player.isPlaying { player.play() }
        lastPCM = pcm
        consecutiveConceals = 0
        player.scheduleBuffer(buffer, completionHandler: nil)
        onOutputLevel?(Self.rmsLevel(pcm))
    }

    /// Bridge a dropped frame so the cadence (and the talking indicator) stays intact.
    /// Cheap PLC: replay the last frame at decaying gain for a frame or two, then silence.
    /// Opus's decoder PLC will replace this once integrated.
    func playConcealment() {
        guard sessionActive else { return }
        consecutiveConceals += 1
        let pcm: Data
        if let last = lastPCM, consecutiveConceals <= 2 {
            pcm = Self.scaled(last, gain: consecutiveConceals == 1 ? 0.6 : 0.3)
        } else {
            pcm = Data(count: frameBytes)   // silence after a sustained drop
        }
        guard let buffer = makeBuffer(from: pcm) else { return }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
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

    /// Scale a 16-bit PCM frame by a linear gain (for concealment fade).
    private static func scaled(_ pcm: Data, gain: Float) -> Data {
        var out = pcm
        out.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<samples.count {
                samples[i] = Int16(max(-32768, min(32767, Float(samples[i]) * gain)))
            }
        }
        return out
    }

    private func encodeAndSend(buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        // Size the output by the sample-rate ratio (e.g. 48 kHz → 16 kHz is 3:1).
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard capacity > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        // Feed the source buffer exactly once; signal "no more" on any re-request so the
        // converter doesn't double-consume the same samples (which garbles the audio).
        // The input block is `@Sendable`, so the "already fed" flag lives in a Sendable box
        // rather than a captured `var` (which strict concurrency flags).
        let fed = FedFlag()
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if fed.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed.value = true
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

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Resilience

    /// Without these, voice silently dies after a phone call, Siri, a route change, or a
    /// media-services reset — the engine stops and never comes back until you rejoin.
    private func registerObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        // Route yanked back to the earpiece (e.g. on a category nudge): re-assert the
        // speaker, but only when actually stuck on the built-in receiver, so we never
        // steal the route from headphones or Bluetooth.
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { _ in
            let session = AVAudioSession.sharedInstance()
            let onReceiver = session.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
            if onReceiver { try? session.overrideOutputAudioPort(.speaker) }
        })

        // Phone call / Siri / other audio: pause on .began, rebuild on .ended.
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended { self.restartEngine() }
        })

        // A config change (route/format) stops the engine; reconnect and restart it.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartEngine()
        })

        // Media services reset: the whole audio stack was torn down — rebuild from scratch.
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartEngine()
        })
    }

    /// Re-activate the session and bring the engine + player back if they stopped.
    private func restartEngine() {
        guard sessionActive else { return }
        do {
            try configureAudioSession()
            engine.connect(player, to: engine.mainMixerNode, format: format)
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            if !player.isPlaying { player.play() }
        } catch {
            // Couldn't recover yet; a later frame or notification will try again.
        }
    }
}
