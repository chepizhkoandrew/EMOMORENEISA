import Foundation
import Observation

// Adapter around the existing AudioRecorder for the onboarding quiz. Exposes
// tap-to-start / tap-to-stop semantics and a live audioLevel binding for the
// on-screen equalizer.
//
// STT is served by OpenAI gpt-4o-transcribe via the proxy (not any on-device
// Speech framework). The default recorder uses a Spanish/English biased prompt
// that hurts Ukrainian recognition, so the adapter overrides it with the
// quiz-language ISO code + a matching preservation hint.

@Observable
final class OnboardingRecorderAdapter {
    private let recorder = AudioRecorder()

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }

    /// Language the user is expected to answer in. STT still accepts any
    /// language (auto-detect fallback in the proxy), but this ISO hint biases
    /// gpt-4o-transcribe toward the correct decoding for the primary case.
    var expectedAnswerLanguage: OnboardingQuizLanguage = .en {
        didSet { applySttHints() }
    }

    init() {
        applySttHints()
    }

    func start() throws {
        applySttHints()
        try recorder.start()
    }

    /// Stops recording and returns the transcribed answer (may be empty).
    func stopAndTranscribe() async -> String {
        return await recorder.stopAndTranscribe()
    }

    func cancel() {
        recorder.cancel()
    }

    private func applySttHints() {
        // The user is explicitly allowed to answer in their native quiz
        // language, in Spanish, or in a mix of both. Constraining STT to a
        // single ISO code (`uk` / `en`) causes Spanish answers to be badly
        // transliterated and destroys code-switched sentences. We therefore
        // leave the language override nil (auto-detect) and only nudge
        // gpt-4o-transcribe via a prompt that lists every language we expect
        // to see in the audio.
        recorder.sttLanguageOverride = nil
        switch expectedAnswerLanguage {
        case .uk:
            recorder.sttPromptOverride = "The speaker may answer in Ukrainian, Spanish, or English — sometimes mixing all three within a single sentence. Preserve Ukrainian letters (і, ї, є, ґ) and Spanish accents (á, é, í, ó, ú, ñ). Preserve proper names, city names, and pet names exactly as spoken."
        case .en:
            recorder.sttPromptOverride = "The speaker may answer in English, Spanish, or a mix of both within a single sentence. Preserve Spanish accents (á, é, í, ó, ú, ñ) and preserve proper names, city names, and pet names exactly as spoken."
        }
    }
}
