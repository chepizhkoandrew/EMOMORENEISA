import Foundation
import Speech
import AVFoundation

final class SpeechService: NSObject {
    private let recognizer: SFSpeechRecognizer? = {
        let locale = Locale(identifier: "es-ES")
        let r = SFSpeechRecognizer(locale: locale)
        let supported = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        let available = supported.contains(locale.identifier)
        glog("🎙  STT  ", "Recognizer locale: es-ES | supported=\(available) | recognizer=\(r != nil ? "✅" : "nil")")
        return r
    }()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var onResult: ((String) -> Void)?
    private var onPartial: ((String) -> Void)?
    private var lastTranscript: String = ""
    private var listenStartTime: Date?

    private let silenceTimeout: TimeInterval = 1.4

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                glog("🎙  STT  ", "Permission: \(status == .authorized ? "granted ✅" : "denied ❌") (rawValue=\(status.rawValue))")
                completion(status == .authorized)
            }
        }
    }

    func startListening(
        contextualStrings: [String] = [],
        onPartialResult: ((String) -> Void)? = nil,
        onFinalResult: @escaping (String) -> Void
    ) {
        stopListening()
        onResult = onFinalResult
        onPartial = onPartialResult
        lastTranscript = ""
        listenStartTime = Date()

        guard let recognizer else {
            glog("🎙  STT  ", "⚠️ SFSpeechRecognizer is nil (locale es-ES not supported on this device?)")
            return
        }
        guard recognizer.isAvailable else {
            glog("🎙  STT  ", "⚠️ Recognizer not available right now")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = false
        if !contextualStrings.isEmpty {
            req.contextualStrings = contextualStrings
            glog("🎙  STT  ", "Contextual hints: \(contextualStrings.joined(separator: ", "))")
        }
        request = req

        // Activate audio session FIRST — this is what makes the format valid on simulator too
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            glog("🎙  STT  ", "⚠️ Audio session activation failed: \(error.localizedDescription)")
            return
        }

        let inputNode = audioEngine.inputNode
        var format = inputNode.outputFormat(forBus: 0)
        glog("🎙  STT  ", "inputNode format — \(format.sampleRate) Hz, \(format.channelCount) ch")

        if format.sampleRate == 0 {
            // On simulator, inputNode reports 0 Hz before the engine runs.
            // Fall back to AVAudioSession's rate, or 44100 Hz as a last resort.
            var sessionRate = AVAudioSession.sharedInstance().sampleRate
            glog("🎙  STT  ", "sampleRate=0 — AVAudioSession rate: \(sessionRate) Hz")
            if sessionRate == 0 { sessionRate = 44100 }
            guard let fallback = AVAudioFormat(standardFormatWithSampleRate: sessionRate, channels: 1) else {
                glog("🎙  STT  ", "⚠️ Cannot construct fallback AVAudioFormat — aborting")
                try? AVAudioSession.sharedInstance().setActive(false)
                return
            }
            format = fallback
            glog("🎙  STT  ", "Using fallback format — \(format.sampleRate) Hz, \(format.channelCount) ch")
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            glog("🎙  STT  ", "Audio engine started ✅ — format \(format.sampleRate) Hz")
        } catch {
            glog("🎙  STT  ", "⚠️ Audio engine start failed: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let elapsed = self.listenStartTime.map { Date().timeIntervalSince($0) } ?? 0
                if text != self.lastTranscript {
                    glog("🎙  STT  ", "Partial [\(String(format: "%.1f", elapsed))s]: '\(text)'")
                }
                self.lastTranscript = text
                DispatchQueue.main.async { self.onPartial?(text) }
                self.resetSilenceTimer()
                if result.isFinal {
                    glog("🎙  STT  ", "isFinal: '\(text)'")
                    self.deliverResult(text)
                }
            }

            if let error {
                let nsErr = error as NSError
                // Code 1110 = no speech detected — not a real error, just silence
                if nsErr.code == 1110 {
                    glog("🎙  STT  ", "No speech detected (1110) — delivering empty")
                } else {
                    glog("🎙  STT  ", "⚠️ Error \(nsErr.code): \(nsErr.localizedDescription)")
                }
                self.deliverResult(self.lastTranscript)
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            let elapsed = self.listenStartTime.map { Date().timeIntervalSince($0) } ?? 0
            glog("🎙  STT  ", "Silence (\(silenceTimeout)s) at [\(String(format: "%.1f", elapsed))s] → '\(self.lastTranscript)'")
            self.deliverResult(self.lastTranscript)
        }
    }

    private func deliverResult(_ text: String) {
        silenceTimer?.invalidate()
        let elapsed = listenStartTime.map { Date().timeIntervalSince($0) } ?? 0
        glog("🎙  STT  ", "✅ Deliver at [\(String(format: "%.1f", elapsed))s]: '\(text)'")
        let cb = onResult
        onResult = nil
        stopListening()
        DispatchQueue.main.async { cb?(text) }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        onPartial = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
