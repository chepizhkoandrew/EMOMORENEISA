import Foundation
import AVFoundation
import Observation

/// State for the two-step song creation flow: genre + length on step one,
/// lyrics/words on step two, then an async server job polled to completion.
@Observable
@MainActor
final class MusicFlowModel {

    // MARK: Step 1 — genre & length
    var selectedGenre: String? = nil
    var length: SongLength = .seconds30

    // MARK: Step 2 — lyrics
    /// Free-form field: explicit lyrics, a pasted text, or a description of
    /// what the song should be about. The server treats it as literal lyrics
    /// when `useAsExactLyrics` is on, otherwise as a brief for the AI writer.
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
    var isPlaying = false

    private var player: AVAudioPlayer? = nil
    private var pollTask: Task<Void, Never>? = nil
    private var playerWatchdog: Timer? = nil

    var canContinue: Bool { selectedGenre != nil }

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
        guard let genre = selectedGenre, canGenerate else { return }
        stopPlayback()
        phase = .submitting
        song = nil

        let text = lyricsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lyrics = useAsExactLyrics ? text : ""
        let description = useAsExactLyrics ? "" : text

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (jobId, _) = try await ProxyClient.shared.musicGenerate(
                    genre: genre,
                    durationSec: length.seconds,
                    lyrics: lyrics,
                    description: description,
                    words: selectedWords,
                    language: LocalizationManager.shared.language.rawValue
                )
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

    // MARK: - Playback

    func togglePlayback() {
        guard let song else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(data: song.audioData)
            player?.prepareToPlay()
        }
        player?.play()
        isPlaying = true
        // AVAudioPlayer has no async completion; a light watchdog flips the
        // button back when the song ends.
        playerWatchdog?.invalidate()
        playerWatchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                if let p = self.player, !p.isPlaying, self.isPlaying {
                    self.isPlaying = false
                    timer.invalidate()
                }
            }
        }
    }

    func startOver() {
        stopPlayback()
        song = nil
        phase = .editing
    }

    func stopPlayback() {
        playerWatchdog?.invalidate()
        playerWatchdog = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    func tearDown() {
        pollTask?.cancel()
        recorder.cancel()
        stopPlayback()
    }
}
