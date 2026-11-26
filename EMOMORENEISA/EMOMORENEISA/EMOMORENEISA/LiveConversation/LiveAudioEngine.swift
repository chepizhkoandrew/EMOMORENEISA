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
/// Callbacks fire on the audio render thread; the owner hops to the main
/// actor itself. Not main-actor isolated on purpose (project default is
/// MainActor) because the tap closure runs on a realtime thread.
nonisolated final class LiveAudioEngine: @unchecked Sendable {
    /// ~100 ms of 16 kHz PCM16 mono, little-endian.
    var onMicChunk: ((Data) -> Void)?
    /// 0…1 input level, ~10× per second (for the UI ring).
    var onMicLevel: ((Float) -> Void)?
    /// Fires when queued tutor audio starts or finishes playing.
    var onPlaybackActiveChanged: ((Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?

    private struct State {
        var muted = false
        var captureEnabled = false
        var pendingBuffers = 0
        var generation = 0
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

    func start() throws {
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        // Must be enabled before formats are read / nodes connected.
        try input.setVoiceProcessingEnabled(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: captureFormat)
        let tapSize = AVAudioFrameCount(max(1024, inFormat.sampleRate / 10))
        input.installTap(onBus: 0, bufferSize: tapSize, format: inFormat) { [weak self] buffer, _ in
            self?.handleMic(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        state.withLock { $0.pendingBuffers = 0; $0.captureEnabled = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    // MARK: - Capture

    private func handleMic(_ buffer: AVAudioPCMBuffer) {
        let (muted, enabled) = state.withLock { ($0.muted, $0.captureEnabled) }
        guard let converter else { return }

        let ratio = captureFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return }

        let n = Int(out.frameLength)
        var sum: Float = 0
        for i in 0..<n { let s = Float(ch[0][i]) / 32768; sum += s * s }
        let rms = sqrt(sum / Float(n))
        onMicLevel?(muted ? 0 : min(1, rms * 6))

        guard enabled, !muted else { return }
        onMicChunk?(Data(bytes: ch[0], count: n * 2))
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

        let (becameActive, gen) = state.withLock { s -> (Bool, Int) in
            s.pendingBuffers += 1
            return (s.pendingBuffers == 1, s.generation)
        }
        if becameActive { onPlaybackActiveChanged?(true) }

        player.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            let becameIdle = self.state.withLock { s -> Bool in
                guard s.generation == gen, s.pendingBuffers > 0 else { return false }
                s.pendingBuffers -= 1
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
