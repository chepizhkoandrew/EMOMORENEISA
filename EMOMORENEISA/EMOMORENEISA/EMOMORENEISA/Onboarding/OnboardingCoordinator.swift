import Foundation
import Observation

// State machine for the voice onboarding quiz.
//
// Ordered flow (Q1 was dropped — name is captured on the pre-form):
//   Q2 → Q3 → Q4 → Q5 → Q6 → Q7
//   → analyst pass 1 → Q8 (adaptive)
//   → analyst pass 2 → Q9 (adaptive)
//   → Q10 → Q11
//   → synthesis (Gemini pro)
//   → closing line (on-the-fly TTS)
//   → persist onto ESPProfile and hand back to caller.
//
// Adaptive slots fall back to the single pre-recorded fallback line when the
// analyst call fails or times out.
//
// Confirmation model: after the user stops recording we DO NOT auto-advance.
// Phase moves to `.reviewingAnswer(slot)` so the user sees their captured
// transcript and taps the forward arrow to confirm (or the back arrow to
// revisit / re-record a prior slot).

@Observable
final class OnboardingCoordinator {
    enum Phase: Equatable {
        case idle
        case playingQuestion(OnboardingSlot)
        case awaitingAnswer(OnboardingSlot)
        case recording(OnboardingSlot)
        case transcribing(OnboardingSlot)
        case reviewingAnswer(OnboardingSlot) // transcript captured, awaiting confirm
        case thinking      // analyst pass or synthesis in-flight
        case closing
        case done
        case failed(String)
    }

    let store: OnboardingStore
    let player = OnboardingAudioPlayer()
    let recorder = OnboardingRecorderAdapter()

    var phase: Phase = .idle
    var lastTranscriptPreview: String = ""
    /// Short localised label shown inside the animated thinking card.
    var thinkingLabel: String = ""

    /// Seconds remaining on the recording hard-cap. Non-zero only while the
    /// user is in `.recording`. Drives the countdown badge in the UI. The
    /// mic is auto-stopped when this hits zero.
    var recordingSecondsRemaining: Int = 0

    /// Hard cap on how long a single answer recording can run before we
    /// auto-stop it and send whatever was captured. Q6 (speak in Spanish)
    /// gets extra time — the user has to formulate and speak a sentence in
    /// a language they're still learning, slowly, which the default cap
    /// doesn't leave room for.
    static let defaultMaxRecordingSeconds: Int = 25
    static let q6MaxRecordingSeconds: Int = 45

    static func maxRecordingSeconds(for slot: OnboardingSlot) -> Int {
        slot == .q6 ? q6MaxRecordingSeconds : defaultMaxRecordingSeconds
    }

    private var recordingTimer: Timer?
    private var recordingAutoStopTask: Task<Void, Never>?

    /// Ordered slot sequence (adaptive slots inserted at fixed positions).
    static let flow: [OnboardingSlot] = [
        .q2, .q3, .q4, .q5, .q5b, .q6, .q7,
        .q8, .q9,
        .q10, .q11
    ]

    init(store: OnboardingStore) {
        self.store = store
    }

    private var analyst: OnboardingAnalyst {
        OnboardingAnalyst(pronoun: store.pronoun ?? .they,
                          quizLanguage: store.quizLanguage)
    }

    // MARK: - Public entry

    /// Kicks off the full quiz. The caller drives the mic tap-to-start via
    /// `recordAnswer()` between prompts.
    @MainActor
    func start() async {
        guard store.pronoun != nil else {
            phase = .failed("pronoun_missing")
            return
        }
        recorder.expectedAnswerLanguage = store.quizLanguage
        await runNext(from: 0)
    }

    /// Called from the UI when the user taps the mic button (or the equalizer
    /// while the question is still playing — that path fades the tutor voice
    /// out and drops straight into recording).
    @MainActor
    func toggleMic() async {
        switch phase {
        case .playingQuestion(let slot):
            // Interrupt-to-answer: gracefully fade the question audio and
            // start listening immediately. The user chose to jump in early.
            print("[ONB-COORD] toggleMic(): interrupting question playback for \(slot) to start recording early")
            await player.fadeOutAndStop(duration: 0.25)
            startRecording(for: slot)
        case .awaitingAnswer(let slot), .reviewingAnswer(let slot):
            // Fresh record OR re-record on a slot the user is reviewing.
            startRecording(for: slot)
        case .recording(let slot):
            await finishRecording(for: slot)
        default:
            break
        }
    }

    @MainActor
    private func startRecording(for slot: OnboardingSlot) {
        do {
            try recorder.start()
            phase = .recording(slot)
            startRecordingCountdown(for: slot)
        } catch {
            print("[ONB-COORD] recorder failed: \(error)")
            phase = .failed("mic_start_failed")
        }
    }

    @MainActor
    private func finishRecording(for slot: OnboardingSlot) async {
        cancelRecordingCountdown()
        phase = .transcribing(slot)
        let transcript = await recorder.stopAndTranscribe()
        lastTranscriptPreview = transcript
        if transcript.trimmingCharacters(in: .whitespaces).isEmpty {
            // The recorder's own duration + peak guards already reject silent
            // or too-quiet takes without ever calling STT, so an empty
            // transcript here is safe: no proxy request was made.
            await player.playBundled(slot: .reprompt,
                                     language: store.quizLanguage,
                                     pronoun: store.pronoun ?? .they)
            phase = .awaitingAnswer(slot)
            return
        }
        store.recordAnswer(slot, transcript: transcript)
        phase = .reviewingAnswer(slot)
    }

    // MARK: - Recording countdown (25s hard cap)

    @MainActor
    private func startRecordingCountdown(for slot: OnboardingSlot) {
        cancelRecordingCountdown()
        recordingSecondsRemaining = Self.maxRecordingSeconds(for: slot)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard case .recording(let s) = self.phase, s == slot else {
                    self.cancelRecordingCountdown()
                    return
                }
                if self.recordingSecondsRemaining > 0 {
                    self.recordingSecondsRemaining -= 1
                }
                if self.recordingSecondsRemaining <= 0 {
                    self.cancelRecordingCountdown()
                    await self.finishRecording(for: slot)
                }
            }
        }
    }

    @MainActor
    private func cancelRecordingCountdown() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingSecondsRemaining = 0
    }

    /// Called from the UI when the user taps the forward (confirm) arrow.
    @MainActor
    func confirmAndAdvance() async {
        guard case .reviewingAnswer(let slot) = phase else { return }
        guard let idx = Self.flow.firstIndex(of: slot) else { return }
        persistAnswerRemotely(slot)
        await runNext(from: idx + 1)
    }

    /// Fire-and-forget mirror of a single confirmed answer to Supabase — the
    /// user has just confirmed this transcript (post any manual edit), so
    /// it's final for this pass. Runs on every confirm, including
    /// re-confirms after a back-navigation re-record (upsert, not insert).
    private func persistAnswerRemotely(_ slot: OnboardingSlot) {
        guard let userId = AuthState.shared.userId,
              let transcript = store.transcripts[slot],
              !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let answer = RemoteOnboardingAnswer(userId: userId, slot: slot.rawValue,
                                            transcript: transcript, recordedAt: Date())
        Task.detached {
            await SupabaseSyncService.shared.upsertOnboardingAnswer(answer)
        }
    }

    /// Called from the UI when the user edits the transcript text after recording.
    /// Updates both the preview and the stored transcript so any subsequent
    /// synthesis or back-navigation picks up the corrected text.
    @MainActor
    func updateTranscript(_ text: String) {
        lastTranscriptPreview = text
        if case .reviewingAnswer(let slot) = phase {
            store.transcripts[slot] = text
        }
    }

    /// Called from the UI when the user taps the back arrow. Jumps to the
    /// previous slot; if that slot already has a captured transcript we go
    /// straight to `.reviewingAnswer`, otherwise we replay its question.
    @MainActor
    func goBackOneSlot() async {
        let currentSlot: OnboardingSlot? = {
            switch phase {
            case .playingQuestion(let s), .awaitingAnswer(let s),
                 .recording(let s), .transcribing(let s), .reviewingAnswer(let s):
                return s
            default: return nil
            }
        }()
        guard let cur = currentSlot,
              let idx = Self.flow.firstIndex(of: cur),
              idx > 0 else { return }
        let prev = Self.flow[idx - 1]
        // Stop anything in flight before jumping.
        player.stop()
        recorder.cancel()
        store.currentSlot = prev
        store.currentQuestionText = OnboardingQuestionBank.text(
            for: prev,
            language: store.quizLanguage,
            pronoun: store.pronoun ?? .they
        )
        // If we already have a transcript for the previous slot, surface it
        // for review; otherwise re-play its question and await a fresh answer.
        if let prevTranscript = store.transcripts[prev],
           !prevTranscript.trimmingCharacters(in: .whitespaces).isEmpty {
            lastTranscriptPreview = prevTranscript
            phase = .reviewingAnswer(prev)
        } else {
            phase = .awaitingAnswer(prev)
        }
    }

    /// True whenever the UI can show a back arrow. Never on the first slot.
    var canGoBack: Bool {
        let currentSlot: OnboardingSlot? = {
            switch phase {
            case .playingQuestion(let s), .awaitingAnswer(let s),
                 .recording(let s), .transcribing(let s), .reviewingAnswer(let s):
                return s
            default: return nil
            }
        }()
        guard let cur = currentSlot,
              let idx = Self.flow.firstIndex(of: cur) else { return false }
        return idx > 0
    }

    // MARK: - Helpers

    @MainActor
    private func enterThinking(label: String) {
        thinkingLabel = label
        phase = .thinking
    }

    /// Move to `.awaitingAnswer(slot)` once question playback/probe work is
    /// done — unless the user already interrupted it (tapped the mic to
    /// answer early — see `toggleMic()`'s `.playingQuestion` case — which
    /// jumps phase to `.recording` immediately, or has since finished
    /// recording/confirmed). Without this guard, the original `runNext` call
    /// resumes after its `await` and unconditionally stomps phase back to
    /// `.awaitingAnswer`, silently dropping the in-progress recording and
    /// making the question look like it "asks again" once the user taps the
    /// now-idle-looking mic a second time.
    @MainActor
    private func settleAwaitingAnswer(_ slot: OnboardingSlot) {
        switch phase {
        case .recording(slot), .transcribing(slot), .reviewingAnswer(slot):
            print("[ONB-COORD] settleAwaitingAnswer(\(slot)) skipped — phase already moved to \(phase)")
        default:
            phase = .awaitingAnswer(slot)
        }
    }

    // MARK: - State machine

    @MainActor
    private func runNext(from index: Int) async {
        guard index < Self.flow.count else {
            await finish()
            return
        }
        let slot = Self.flow[index]
        store.currentSlot = slot

        // If the user already answered this slot on a previous pass through
        // the flow (i.e. they went back with the arrow and are now walking
        // forward again), don't re-play the question and don't wipe their
        // captured answer — jump straight to `.reviewingAnswer` so the
        // transcript is visible and they can either confirm forward again
        // or tap the mic to re-record. This is the fix for the R14 bug
        // "back → forward → back → forward loses answers".
        if let existing = store.transcripts[slot],
           !existing.trimmingCharacters(in: .whitespaces).isEmpty {
            // For adaptive slots make sure the subtitle text still reflects
            // the probe wording (fall back to the cached probe if we have it).
            if slot == .q8, let cached = store.probes[1] {
                store.currentQuestionText = cached.nextQuestionText
            } else if slot == .q9, let cached = store.probes[2] {
                store.currentQuestionText = cached.nextQuestionText
            } else {
                store.currentQuestionText = OnboardingQuestionBank.text(
                    for: slot,
                    language: store.quizLanguage,
                    pronoun: store.pronoun ?? .they
                )
            }
            lastTranscriptPreview = existing
            phase = .reviewingAnswer(slot)
            return
        }

        if slot == .q8 {
            // Reuse a cached probe when the user has navigated back and
            // forward — no need to re-bill Gemini for the same input set.
            if let cached = store.probes[1] {
                print("[ONB-COORD] q8: using cached probe")
                store.currentQuestionText = cached.nextQuestionText
                await playDynamicQuestion(slot: .q8, text: cached.nextQuestionText)
                settleAwaitingAnswer(.q8)
                return
            }
            enterThinking(label: store.quizLanguage == .uk
                ? "Аналізую твої відповіді…"
                : "Thinking about you…")
            if let probe = await analyst.probe(pass: 1, transcripts: store.transcripts) {
                print("[ONB-COORD] q8: probe pass 1 succeeded — playing generated question")
                store.probes[1] = probe
                store.currentQuestionText = probe.nextQuestionText
                await playDynamicQuestion(slot: .q8, text: probe.nextQuestionText)
            } else {
                print("[ONB-COORD] q8: probe pass 1 failed/timed out — playing fallback line")
                await playFallback(for: .q8)
            }
            settleAwaitingAnswer(.q8)
            return
        }
        if slot == .q9 {
            if let cached = store.probes[2] {
                print("[ONB-COORD] q9: using cached probe")
                store.currentQuestionText = cached.nextQuestionText
                await playDynamicQuestion(slot: .q9, text: cached.nextQuestionText)
                settleAwaitingAnswer(.q9)
                return
            }
            enterThinking(label: store.quizLanguage == .uk
                ? "Ще одна персональна думка…"
                : "One more personal question…")
            let prev: [String: String]? = store.probes[1].map { p in
                [
                    "next_question_text": p.nextQuestionText,
                    "target_slot": p.targetSlot,
                    "reasoning": p.reasoning
                ]
            }
            if let probe = await analyst.probe(pass: 2,
                                               transcripts: store.transcripts,
                                               previousProbe: prev) {
                print("[ONB-COORD] q9: probe pass 2 succeeded — playing generated question")
                store.probes[2] = probe
                store.currentQuestionText = probe.nextQuestionText
                await playDynamicQuestion(slot: .q9, text: probe.nextQuestionText)
            } else {
                print("[ONB-COORD] q9: probe pass 2 failed/timed out — playing fallback line")
                await playFallback(for: .q9)
            }
            settleAwaitingAnswer(.q9)
            return
        }

        // Pre-recorded standard / finale slot. When there's no bundled asset
        // shipped, we fall back to a live TTS fetch which can introduce a
        // visible network round-trip before audio starts — surface that as
        // `.thinking` first so the UI shows a loading indicator instead of an
        // empty equalizer, then swap to `.playingQuestion` right as playback
        // actually starts.
        let text = OnboardingQuestionBank.text(
            for: slot,
            language: store.quizLanguage,
            pronoun: store.pronoun ?? .they
        )
        store.currentQuestionText = text
        if let bundleURL = OnboardingQuestionBank.bundleAudioURL(
            for: slot,
            language: store.quizLanguage,
            pronoun: store.pronoun ?? .they
        ) {
            print("[ONB-COORD] \(slot): playing bundled audio")
            phase = .playingQuestion(slot)
            await player.playPrefetched(url: bundleURL)
        } else {
            print("[ONB-COORD] \(slot): no bundled audio — prefetching dynamic TTS")
            phase = .thinking
            if let tmp = await player.prefetchDynamic(text: text) {
                phase = .playingQuestion(slot)
                await player.playPrefetched(url: tmp)
            } else {
                print("[ONB-COORD] \(slot): dynamic TTS prefetch failed — proceeding with no audio")
            }
        }
        settleAwaitingAnswer(slot)
    }

    @MainActor
    private func playDynamicQuestion(slot: OnboardingSlot, text: String) async {
        phase = .playingQuestion(slot)
        await player.playDynamic(text: text)
    }

    @MainActor
    private func playFallback(for slot: OnboardingSlot) async {
        let text = OnboardingQuestionBank.text(
            for: .fallback,
            language: store.quizLanguage,
            pronoun: store.pronoun ?? .they
        )
        store.currentQuestionText = text
        phase = .playingQuestion(slot)
        await player.playBundled(slot: .fallback,
                                 language: store.quizLanguage,
                                 pronoun: store.pronoun ?? .they)
    }

    @MainActor
    private func finish() async {
        print("[ONB-COORD] finish(): entering synthesis")
        enterThinking(label: store.quizLanguage == .uk
            ? "Зберігаю твій профіль… майже готово."
            : "Saving your profile… almost there.")
        guard let syn = await analyst.synthesize(transcripts: store.transcripts,
                                                 probes: store.probes) else {
            print("[ONB-COORD] finish(): synthesis failed — surfacing .failed")
            phase = .failed("synthesis_failed")
            return
        }
        print("[ONB-COORD] finish(): synthesis succeeded — playing closing line")
        store.synthesis = syn

        // Closing line: on-the-fly TTS, warm greeting using the confirmed name.
        phase = .closing
        let name = store.name.trimmingCharacters(in: .whitespaces)
        let closingText: String
        switch store.quizLanguage {
        case .en:
            closingText = name.isEmpty
                ? "Nice to meet you. This is going to be a really fun ride — let's go."
                : "Nice to meet you, \(name). This is going to be a really fun ride — let's go."
        case .uk:
            closingText = name.isEmpty
                ? "Дуже приємно. Обіцяю — ця подорож буде класна. Погнали."
                : "Дуже приємно, \(name). Обіцяю — ця подорож буде класна. Погнали."
        }
        store.currentQuestionText = closingText
        await player.playDynamic(text: closingText)
        print("[ONB-COORD] finish(): closing line finished — phase = .done")
        phase = .done
    }
}
