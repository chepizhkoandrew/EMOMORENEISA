import AVFoundation
import Observation

@Observable
final class AudioRecorder {
    var isRecording = false
    var audioLevel: Float = 0.0

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var audioFileURL: URL?
    private var recordingStartTime: Date?
    private var peakLevel: Float = 0

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        print("[STT] start() — setting category .playAndRecord")
        try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true)
        print("[STT] AVAudioSession active — category: \(session.category.rawValue), inputs: \(session.availableInputs?.map { $0.portName } ?? [])")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        audioFileURL = url
        recordingStartTime = Date()
        peakLevel = 0
        print("[STT] Recording to: \(url.lastPathComponent)")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        let started = recorder?.record() ?? false
        isRecording = true
        print("[STT] recorder.record() → \(started ? "✅ started" : "❌ FAILED to start")")

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.recorder?.updateMeters()
            let level = self?.recorder?.averagePower(forChannel: 0) ?? -60
            let normalized = max(0, (level + 60) / 60)
            DispatchQueue.main.async {
                self?.audioLevel = normalized
                if normalized > (self?.peakLevel ?? 0) {
                    self?.peakLevel = normalized
                }
            }
        }
    }

    func stopAndTranscribe() async -> String {
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        audioLevel = 0

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let peak = peakLevel
        recordingStartTime = nil
        peakLevel = 0

        print("[STT] stopAndTranscribe — duration: \(String(format: "%.2f", duration))s, peak: \(String(format: "%.3f", peak))")

        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = audioFileURL else {
            print("[STT] ⚠️ No audio file URL — aborting")
            return ""
        }
        audioFileURL = nil

        guard duration >= 0.8 else {
            print("[STT] ❌ Recording too short (\(String(format: "%.2f", duration))s) — skipping")
            try? FileManager.default.removeItem(at: url)
            return ""
        }

        guard peak > 0.06 else {
            print("[STT] ❌ Recording too quiet (peak=\(String(format: "%.3f", peak))) — skipping (threshold=0.06)")
            try? FileManager.default.removeItem(at: url)
            return ""
        }

        print("[STT] ✅ Recording passed guards — duration: \(String(format: "%.2f", duration))s, peak: \(String(format: "%.3f", peak))")
        let result = await transcribeViaProxy(url: url)
        print("[STT] Final transcript: '\(result)'")
        try? FileManager.default.removeItem(at: url)
        return result
    }

    func cancel() {
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        audioLevel = 0
        recordingStartTime = nil
        peakLevel = 0
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
            audioFileURL = nil
        }
    }

    // MARK: - Proxy STT (OpenAI gpt-4o-transcribe, server-side)

    private func transcribeViaProxy(url: URL) async -> String {
        guard let audioData = try? Data(contentsOf: url), !audioData.isEmpty else {
            print("[STT] Audio file missing or empty")
            return ""
        }
        print("[STT] Audio file size: \(audioData.count) bytes — sending to proxy…")
        do {
            let transcript = try await ProxyClient.shared.transcribe(
                audioData: audioData,
                mime: "audio/mp4",
                prompt: "Spanish/English speech. Preserve exact word endings and Spanish accents (á, é, í, ó, ú, ñ)."
            )
            if transcript.isEmpty {
                print("[STT] Proxy returned empty/no speech")
                return ""
            }
            print("[STT] Proxy transcript: \(transcript.prefix(100))")
            return transcript
        } catch {
            print("[STT] Proxy error: \(error)")
            return ""
        }
    }
}
