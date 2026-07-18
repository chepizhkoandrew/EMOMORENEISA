import Foundation
import Observation

/// State for the two-step song creation flow: genre + length on step one,
/// lyrics/words on step two, then an async server job polled to completion.
@Observable
@MainActor
final class MusicFlowModel {

    // MARK: Step 1 — genre & length
    /// Up to 3 genres, blended into one style tag list for the model. Starts
    /// pre-selected with a sensible default so "Pick Lyrics" is enabled the
    /// instant the screen appears.
    var selectedGenres: [String] = ["Reggaetón"]
    static let maxGenres = 3
    var length: SongLength = .seconds30

    // MARK: Step 2 — lyrics
    /// Free-form field: explicit lyrics, a pasted text, or a description of
    /// what the song should be about. The server treats it as literal lyrics
    /// when `useAsExactLyrics` is on, otherwise as a brief for the AI writer
    /// to expand into a full structured (multi-line, titled) song.
    ///
    /// Was forced permanently `true` earlier — turned out to silently starve
    /// the whole karaoke system: with the text sung verbatim and no AI
    /// expansion, a short one-sentence input became ONE unbroken lyric line,
    /// which caps the picture-scene planner at exactly 1 scene (it operates
    /// per line — no second line, no second scene, structurally), and the
    /// title never got generated either (only the AI lyrics writer sets a
    /// title; skipping it left the title showing the genre list instead).
    /// Defaults OFF so the common case — a short typed brief — gets expanded
    /// into a proper song; ON is for someone pasting/dictating complete,
    /// already-multi-line lyrics they want sung exactly as written.
    var lyricsText: String = ""
    var useAsExactLyrics: Bool = false
    /// Spanish words/phrases picked from the memorize queue.
    var selectedWords: [String] = []

    // MARK: Speak-to-describe (same STT pipeline as the onboarding quiz)
    let recorder = AudioRecorder()
    var isTranscribing = false

    // MARK: Generation
    enum Phase: Equatable {
        case editing
        case submitting
        case working(stage: String) // server job status key
        case ready
        case failed(message: String)
    }
    var phase: Phase = .editing
    var song: ProxyClient.MusicSong? = nil
    /// Set by the view once the finished song is saved into "My Songs", so a
    /// view re-render can't save the same song twice.
    var songPersisted = false
    /// The "My Songs" record for the finished song — what the result screen's
    /// share button hands to ShareSongSheet.
    var savedSong: SavedSong? = nil

    /// Server's own render-time estimate for the current job (returned at job
    /// creation — mirrors its `duration >= 120 ? 180 : 120` eta) plus the
    /// alignment pass, and when the working screen started, so the progress
    /// bar can ramp toward this instead of guessing client-side.
    var etaSeconds: Int = 120
    var workingStartedAt: Date? = nil

    private var pollTask: Task<Void, Never>? = nil

    var canContinue: Bool { !selectedGenres.isEmpty }

    func toggleGenre(_ genre: String) {
        if let idx = selectedGenres.firstIndex(of: genre) {
            selectedGenres.remove(at: idx)
        } else if selectedGenres.count < Self.maxGenres {
            selectedGenres.append(genre)
        }
    }

    var canGenerate: Bool {
        guard case .editing = phase, canContinue else {
            if case .failed = phase, canContinue { return hasAnyContent }
            return false
        }
        return hasAnyContent
    }

    private var hasAnyContent: Bool {
        !selectedWords.isEmpty || !lyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleWord(_ word: String) {
        if let idx = selectedWords.firstIndex(of: word) {
            selectedWords.remove(at: idx)
        } else {
            selectedWords.append(word)
        }
    }

    // MARK: - Speak button

    func toggleMic() async {
        if recorder.isRecording {
            isTranscribing = true
            recorder.sttLanguageOverride = nil
            let transcript = await recorder.stopAndTranscribe()
            isTranscribing = false
            if !transcript.isEmpty {
                if lyricsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lyricsText = transcript
                } else {
                    lyricsText += "\n" + transcript
                }
            }
        } else {
            // Bias STT toward the mixed-language way users describe songs.
            recorder.sttPromptOverride = "The speaker describes a song they want: topic, mood, and Spanish words to include. Preserve Spanish accents (á, é, í, ó, ú, ñ)."
            try? recorder.start()
        }
    }

    // MARK: - Generation

    func generate() {
        guard canContinue, canGenerate else { return }
        let genre = selectedGenres.joined(separator: ", ")
        phase = .submitting
        song = nil
        songPersisted = false
        savedSong = nil

        let text = lyricsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lyrics = useAsExactLyrics ? text : ""
        let description = useAsExactLyrics ? "" : text

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (jobId, eta) = try await ProxyClient.shared.musicGenerate(
                    genre: genre,
                    durationSec: length.seconds,
                    lyrics: lyrics,
                    description: description,
                    words: selectedWords,
                    language: LocalizationManager.shared.language.rawValue
                )
                // +20s pads the server's render-only eta for the whisper
                // alignment pass that runs after the audio finishes.
                self.etaSeconds = eta + 20
                self.workingStartedAt = Date()
                self.phase = .working(stage: "queued")
                await WalletManager.shared.refresh()
                try await self.poll(jobId: jobId)
            } catch is CancellationError {
                // user left the screen — nothing to do
            } catch let ProxyError.insufficientTreats(_) {
                self.phase = .editing // paywall is already being shown by ProxyClient
            } catch {
                self.phase = .failed(message: error.localizedDescription)
            }
        }
    }

    private func poll(jobId: String) async throws {
        // Song jobs run 15s–3min (cold GPU starts load the model first).
        // Poll gently; the job is held server-side for 30 min.
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try Task.checkCancellation()
            let state = try await ProxyClient.shared.musicJob(id: jobId)
            switch state {
            case .queued: phase = .working(stage: "queued")
            case .writingLyrics: phase = .working(stage: "writing_lyrics")
            case .generating: phase = .working(stage: "generating")
            case .failed(let message):
                phase = .failed(message: message)
                return
            case .done(let result):
                song = result
                phase = .ready
                return
            }
        }
        phase = .failed(message: "timeout")
    }

    func startOver() {
        song = nil
        songPersisted = false
        savedSong = nil
        phase = .editing
    }

    func tearDown() {
        pollTask?.cancel()
        recorder.cancel()
    }
}
