import AVFoundation
import os

/// Full-duplex audio for a Live Conversation call.
///
/// - Capture: mic → (voice processing: echo cancellation + noise suppression,
///   so the tutor never hears itself through the speaker and the user can
///   barge in) → 16 kHz mono PCM16 chunks of ~100 ms → `onMicChunk`.
/// - Playback: 24 kHz mono PCM16 from Gemini → scheduled back-to-back on an
///   `AVAudioPlayerNode`. `flush()` drops everything queued (barge-in).
///
/// Robustness (TestFlight build 168 was silent both ways):
/// - iOS stops an AVAudioEngine whenever its I/O configuration changes
///   (voice processing switching on, route → speaker, Bluetooth, …) and only
///   posts `AVAudioEngineConfigurationChange`. We observe it and rebuild the
///   tap + restart, and also re-check `isRunning` right after starting.
/// - The voice-processed input can be multi-channel on some iPhones; we take
///   channel 0 ourselves instead of asking AVAudioConverter to downmix.
///
/// Callbacks fire on audio threads; the owner hops to the main actor itself.
nonisolated final class LiveAudioEngine: @unchecked Sendable {
    /// ~100 ms of 16 kHz PCM16 mono, little-endian.
    var onMicChunk: ((Data) -> Void)?
    /// 0…1 input level, ~10× per second (for the UI ring).
    var onMicLevel: ((Float) -> Void)?
    /// Fires when queued tutor audio starts or finishes playing.
    var onPlaybackActiveChanged: ((Bool) -> Void)?

    /// Snapshot for remote diagnostics (sent to the relay log).
    struct Stats {
        var micCallbacks = 0
        var micChunks = 0
        var micConvertErrors = 0
        var buffersScheduled = 0
        var buffersPlayed = 0
        var configChanges = 0
        var restarts = 0
        var lastError = ""
        var inputFormat = ""
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var monoInFormat: AVAudioFormat?
    private var configObserver: NSObjectProtocol?

    private struct State {
        var muted = false
        var captureEnabled = false
        var pendingBuffers = 0
        var generation = 0
        var stats = Stats()
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var running = false

    var isMuted: Bool {
        get { state.withLock { $0.muted } }
        set { state.withLock { $0.muted = newValue } }
    }

    /// Mic chunks are only emitted while this is true (off during reconnects).
    var captureEnabled: Bool {
        get { state.withLock { $0.captureEnabled } }
        set { state.withLock { $0.captureEnabled = newValue } }
    }

    var stats: Stats { state.withLock { $0.stats } }
    var engineRunning: Bool { engine.isRunning }

    func start() throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])

        // Must be enabled before formats are read / nodes connected.
        try engine.inputNode.setVoiceProcessingEnabled(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        installTap()

        engine.prepare()
        try engine.start()
        player.play()
        running = true

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        // The I/O change from enabling voice processing can stop the engine a
        // beat after start() returns; catch that too.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.running, !self.engine.isRunning else { return }
            self.handleConfigurationChange()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        state.withLock { $0.pendingBuffers = 0; $0.captureEnabled = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    // MARK: - Engine (re)configuration

    private func installTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inFormat = input.outputFormat(forBus: 0)
        state.withLock { $0.stats.inputFormat = "\(Int(inFormat.sampleRate))Hz/\(inFormat.channelCount)ch" }
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            state.withLock { $0.stats.lastError = "input format invalid" }
            return
        }
        // We feed the converter a mono float buffer built from channel 0.
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inFormat.sampleRate, channels: 1, interleaved: false)!
        monoInFormat = mono
        converter = AVAudioConverter(from: mono, to: captureFormat)
        let tapSize = AVAudioFrameCount(max(1024, inFormat.sampleRate / 10))
        input.installTap(onBus: 0, bufferSize: tapSize, format: inFormat) { [weak self] buffer, _ in
            self?.handleMic(buffer)
        }
    }

    private func handleConfigurationChange() {
        guard running else { return }
        state.withLock { $0.stats.configChanges += 1 }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.flush()
            self.installTap()
            if !self.engine.isRunning {
                do {
                    self.engine.prepare()
                    try self.engine.start()
                    self.state.withLock { $0.stats.restarts += 1 }
                } catch {
                    self.state.withLock { $0.stats.lastError = "restart: \(error.localizedDescription)" }
                }
            }
            if !self.player.isPlaying { self.player.play() }
        }
    }

    // MARK: - Capture

    private func handleMic(_ buffer: AVAudioPCMBuffer) {
        let (muted, enabled) = state.withLock { s -> (Bool, Bool) in
            s.stats.micCallbacks += 1
            return (s.muted, s.captureEnabled)
        }
        guard let converter, let monoInFormat, buffer.frameLength > 0 else { return }

        // Channel 0 → mono float buffer (works for any input channel count).
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoInFormat, frameCapacity: buffer.frameLength) else { return }
        mono.frameLength = buffer.frameLength
        let n = Int(buffer.frameLength)
        if let src = buffer.floatChannelData {
            mono.floatChannelData![0].update(from: src[0], count: n)
        } else if let src = buffer.int16ChannelData {
            let dst = mono.floatChannelData![0]
            for i in 0..<n { dst[i] = Float(src[0][i]) / 32768 }
        } else {
            return
        }

        let ratio = captureFormat.sampleRate / monoInFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(n) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return mono
        }
        guard error == nil, out.frameLength > 0, let ch = out.int16ChannelData else {
            let message = error.map { "convert: \($0.localizedDescription)" }
            state.withLock { s in
                s.stats.micConvertErrors += 1
                if let message { s.stats.lastError = message }
            }
            return
        }

        let m = Int(out.frameLength)
        var sum: Float = 0
        for i in 0..<m { let s = Float(ch[0][i]) / 32768; sum += s * s }
        let rms = sqrt(sum / Float(m))
        onMicLevel?(muted ? 0 : min(1, rms * 6))

        guard enabled, !muted else { return }
        state.withLock { $0.stats.micChunks += 1 }
        onMicChunk?(Data(bytes: ch[0], count: m * 2))
    }

    // MARK: - Playback

    /// Queue a chunk of 24 kHz PCM16 mono from the model.
    func enqueue(pcm16 data: Data) {
        guard running else { return }
        let frames = data.count / 2
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        let dst = buf.floatChannelData![0]
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<frames { dst[i] = Float(Int16(littleEndian: src[i])) / 32768 }
        }

        if !engine.isRunning { handleConfigurationChange() }

        let (becameActive, gen) = state.withLock { s -> (Bool, Int) in
            s.pendingBuffers += 1
            s.stats.buffersScheduled += 1
            return (s.pendingBuffers == 1, s.generation)
        }
        if becameActive { onPlaybackActiveChanged?(true) }

        player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            let becameIdle = self.state.withLock { s -> Bool in
                guard s.generation == gen, s.pendingBuffers > 0 else { return false }
                s.pendingBuffers -= 1
                s.stats.buffersPlayed += 1
                return s.pendingBuffers == 0
            }
            if becameIdle { self.onPlaybackActiveChanged?(false) }
        }
        if !player.isPlaying { player.play() }
    }

    /// Drop all queued tutor audio immediately (user interrupted).
    func flush() {
        guard running else { return }
        let wasActive = state.withLock { s -> Bool in
            let active = s.pendingBuffers > 0
            s.pendingBuffers = 0
            s.generation += 1
            return active
        }
        player.stop()
        player.play()
        if wasActive { onPlaybackActiveChanged?(false) }
    }
}
