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

    private var geminiAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String ?? ""
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        audioFileURL = url
        recordingStartTime = Date()
        peakLevel = 0

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()
        isRecording = true

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

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = audioFileURL else { return "" }
        audioFileURL = nil

        guard duration >= 0.8 else {
            print("[STT] Recording too short (\(String(format: "%.2f", duration))s) — skipping")
            try? FileManager.default.removeItem(at: url)
            return ""
        }

        guard peak > 0.06 else {
            print("[STT] Recording too quiet (peak=\(String(format: "%.3f", peak))) — skipping")
            try? FileManager.default.removeItem(at: url)
            return ""
        }

        let result = await transcribeWithGemini(url: url)
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
            audioFileURL = nil
        }
    }

    // MARK: - Gemini Flash STT

    private func transcribeWithGemini(url: URL) async -> String {
        guard let audioData = try? Data(contentsOf: url), !audioData.isEmpty else {
            print("[STT] Audio file missing or empty")
            return ""
        }
        print("[STT] Audio file size: \(audioData.count) bytes")
        let key = geminiAPIKey
        guard !key.isEmpty, !key.hasPrefix("$("),
              let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(key)") else {
            print("[STT] Gemini key missing: '\(key.prefix(12))…'")
            return ""
        }
        print("[STT] Sending to Gemini STT…")

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "inlineData": [
                                "mimeType": "audio/mp4",
                                "data": audioData.base64EncodedString()
                            ]
                        ],
                        [
                            "text": "You are a transcription engine. Listen to the audio and transcribe what is spoken. The speaker may use English, Spanish, or both. Add correct Spanish accent marks (á, é, í, ó, ú, ñ) where needed. If the audio contains no speech, is silent, or is unclear, respond with exactly the string: [EMPTY]. Return ONLY the transcribed words — nothing else."
                        ]
                    ],
                    "role": "user"
                ]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
                print("[STT] Gemini HTTP \(status): \(snippet)")
                return ""
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let candidates = json["candidates"] as? [[String: Any]],
                let firstCandidate = candidates.first,
                let content = firstCandidate["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]],
                let firstPart = parts.first,
                let text = firstPart["text"] as? String
            else {
                print("[STT] Gemini unexpected response")
                return ""
            }

            let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if transcript == "[EMPTY]" || transcript.isEmpty {
                print("[STT] Gemini returned empty/no speech")
                return ""
            }

            print("[STT] Gemini transcript: \(transcript.prefix(100))")
            return transcript
        } catch {
            print("[STT] Gemini error: \(error)")
            return ""
        }
    }
}
