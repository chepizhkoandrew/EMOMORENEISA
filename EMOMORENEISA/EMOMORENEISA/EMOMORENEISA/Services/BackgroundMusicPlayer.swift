@preconcurrency import AVFoundation

// MARK: - Onboarding voice audio manager

final class OnboardAudioManager {
    static let shared = OnboardAudioManager()
    private init() {}

    private var player: AVAudioPlayer?

    func play(named name: String, fallback: String? = nil, volume: Float = 0.85) {
        stop()
        let url = Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? fallback.flatMap { Bundle.main.url(forResource: $0, withExtension: "mp3") }
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = volume
            player?.play()
        } catch {}
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

// MARK: - Slot machine spin sound

@MainActor
final class SlotSpinSoundPlayer {
    static let shared = SlotSpinSoundPlayer()

    private var player: AVAudioPlayer?

    private init() {
        guard let url = Bundle.main.url(forResource: "slot_spin", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0.55
            player?.prepareToPlay()
        } catch {}
    }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        if !player.isPlaying { player.play() }
    }

    func stop() {
        player?.stop()
    }
}

// MARK: - Background music

@MainActor
final class BackgroundMusicPlayer {
    static let shared = BackgroundMusicPlayer()

    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?
    private let targetVolume: Float = 0.18

    private init() {
        guard let url = Bundle.main.url(forResource: "background_music", withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
        } catch {}
    }

    func play() {
        guard let player else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if !player.isPlaying { player.play() }
        fade(to: targetVolume, duration: 1.2)
    }

    func fadeOut(duration: TimeInterval = 1.5) {
        fade(to: 0, duration: duration) { [weak self] in
            self?.player?.pause()
        }
    }

    func setMuted(_ muted: Bool) {
        fade(to: muted ? 0 : targetVolume, duration: 0.35)
    }

    private func fade(to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard let player else { completion?(); return }
        let steps = 30
        let interval = duration / Double(steps)
        let start = player.volume
        let delta = (target - start) / Float(steps)
        var step = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            step += 1
            player.volume = max(0, min(1, start + delta * Float(step)))
            if step >= steps {
                t.invalidate()
                player.volume = target
                if self?.fadeTimer === t { self?.fadeTimer = nil }
                completion?()
            }
        }
    }
}
