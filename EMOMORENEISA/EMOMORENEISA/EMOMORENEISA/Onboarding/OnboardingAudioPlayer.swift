import AVFoundation
import Observation

// Voice player for the onboarding quiz. For pre-recorded slots it plays the
// bundled `.aac` shipped by the render script; for adaptive Q8/Q9 and the
// closing line it fetches on-the-fly TTS through the existing proxy — which is
// pinned to the SAME activeVoiceTag() as the pre-recorded assets, so the voice
// stays seamless.

@Observable
final class OnboardingAudioPlayer: NSObject {
    var isPlaying: Bool = false

    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Play a pre-recorded slot from the app bundle. Returns when playback
    /// finishes (or immediately if the asset is missing).
    func playBundled(slot: OnboardingSlot,
                     language: OnboardingQuizLanguage,
                     pronoun: UserPronoun) async {
        if let url = OnboardingQuestionBank.bundleAudioURL(
            for: slot, language: language, pronoun: pronoun
        ) {
            await play(url: url)
            return
        }
        // No pre-rendered asset shipped in this build — fall back to on-the-fly
        // TTS through the proxy. Voice tag is pinned on the server, so the
        // fallback still uses the same voice as (future) bundled assets.
        let text = OnboardingQuestionBank.text(for: slot, language: language, pronoun: pronoun)
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            print("[ONB-AUDIO] Missing bundle asset for \(slot) \(language.rawValue)/\(pronoun.rawValue) — using dynamic TTS")
            await playDynamic(text: text)
        } else {
            print("[ONB-AUDIO] Missing bundle asset AND empty text for \(slot) \(language.rawValue)/\(pronoun.rawValue)")
        }
    }

    /// Fetch on-the-fly TTS from the proxy (Gemini/Cloud-TTS via same voice tag)
    /// and play it. Used for Q8, Q9 and the closing line.
    func playDynamic(text: String) async {
        guard let tmp = await prefetchDynamic(text: text) else { return }
        await play(url: tmp)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Fetch on-the-fly TTS to a temp file and return the URL WITHOUT playing.
    /// Callers can flip UI state to `.playingQuestion` before invoking
    /// `play(url:)` so the network delay is surfaced as a loading beat
    /// rather than a mysteriously silent equalizer.
    func prefetchDynamic(text: String) async -> URL? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        do {
            let (raw, mime) = try await ProxyClient.shared.tts(text: text, context: "sentence")
            let ext: String
            let m = mime.lowercased()
            if m.hasPrefix("audio/aac") { ext = "aac" }
            else if m.hasPrefix("audio/mp4") || m.hasPrefix("audio/m4a") || m.hasPrefix("audio/x-m4a") { ext = "m4a" }
            else { ext = "wav" }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("onb-\(UUID().uuidString).\(ext)")
            try raw.write(to: tmp)
            return tmp
        } catch {
            print("[ONB-AUDIO] dynamic TTS failed: \(error)")
            return nil
        }
    }

    /// Public wrapper around the private `play(url:)` used by callers that
    /// prefetched via `prefetchDynamic(text:)` and want to control the
    /// phase transition themselves. Only tmp files (path contains
    /// NSTemporaryDirectory) are auto-deleted; bundled assets are left alone.
    func playPrefetched(url: URL) async {
        await play(url: url)
        let tmpDir = FileManager.default.temporaryDirectory.path
        if url.path.hasPrefix(tmpDir) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        continuation?.resume()
        continuation = nil
    }

    /// Gradually fade the current playback volume to zero over `duration`
    /// seconds, then hard-stop. Used when the user interrupts the tutor
    /// mid-question by tapping the equalizer to start recording — we don't
    /// want an abrupt cut, we want a graceful hand-off.
    func fadeOutAndStop(duration: TimeInterval = 0.25) async {
        guard let p = player, p.isPlaying else {
            stop()
            return
        }
        let steps = 10
        let stepDelay = duration / Double(steps)
        let startVolume = p.volume
        for i in 0..<steps {
            let v = startVolume * Float(1.0 - Double(i + 1) / Double(steps))
            p.volume = max(0, v)
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }
        stop()
    }

    @MainActor
    private func play(url: URL) async {
        // Prepare audio session for playback (recorder switches it back on start()).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            isPlaying = true
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.continuation = cont
                p.play()
            }
        } catch {
            print("[ONB-AUDIO] play(url) error: \(error)")
        }
    }
}

extension OnboardingAudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        self.player = nil
        continuation?.resume()
        continuation = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
        self.player = nil
        continuation?.resume()
        continuation = nil
    }
}
