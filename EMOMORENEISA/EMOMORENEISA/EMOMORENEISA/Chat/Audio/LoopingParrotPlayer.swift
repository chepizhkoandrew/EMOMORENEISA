import Foundation
import AVFoundation
import MediaPlayer

@Observable
final class LoopingParrotPlayer: NSObject {

    var isPlaying: Bool = false
    var currentLoop: Int = 0
    var currentSegment: Int = 0
    var totalLoops: Int = 4
    var isDone: Bool = false

    private var segmentURLs: [URL] = []
    private var player: AVAudioPlayer?
    private var phrase: ParrotPhrase?
    private let segmentPause: TimeInterval = 0.4

    // Streaming mode: segment files appear on disk over time, so we resolve each
    // segment URL on demand and buffer (poll) when a file is not ready yet.
    private var streaming = false
    private var expectedSegments = 7
    private var parrotDir: URL?
    private let bufferPollInterval: TimeInterval = 0.2
    private let bufferMaxPolls = 150 // ~30s ceiling before giving up on a segment
    private var bufferPolls = 0

    func start(phrase: ParrotPhrase, loops: Int) {
        guard phrase.hasAudio else { return }
        self.streaming = false
        self.phrase = phrase
        self.segmentURLs = phrase.segmentURLs
        self.expectedSegments = phrase.segmentURLs.count
        self.totalLoops = max(1, loops)
        self.currentLoop = 0
        self.currentSegment = 0
        self.isDone = false

        setupAudioSession()
        setupRemoteCommands()
        playCurrentSegment()
    }

    // Begin playback while segments are still being written to `parrotDir` as
    // `1.wav...N.wav`. Plays each as soon as it lands; buffers in between.
    func startStreaming(phrase: ParrotPhrase, loops: Int, expectedSegments: Int) {
        self.streaming = true
        self.phrase = phrase
        self.segmentURLs = []
        self.parrotDir = ParrotPhrase.parrotDir(for: phrase.id)
        self.expectedSegments = max(1, expectedSegments)
        self.totalLoops = max(1, loops)
        self.currentLoop = 0
        self.currentSegment = 0
        self.isDone = false
        self.bufferPolls = 0

        setupAudioSession()
        setupRemoteCommands()
        playCurrentSegment()
    }

    private var segmentCount: Int { streaming ? expectedSegments : segmentURLs.count }

    private func urlForSegment(_ i: Int) -> URL? {
        if streaming {
            guard let dir = parrotDir else { return nil }
            // Segments may arrive as AAC (compressed) or WAV (legacy PCM); accept
            // whichever file ParrotService wrote for this position.
            for ext in ["aac", "m4a", "wav"] {
                let url = dir.appendingPathComponent("\(i + 1).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
            return nil
        }
        return i < segmentURLs.count ? segmentURLs[i] : nil
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        teardownRemoteCommands()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func skipToPreviousSegment() {
        player?.stop()
        player = nil
        if currentSegment > 0 {
            currentSegment -= 1
        } else if currentLoop > 0 {
            currentLoop -= 1
            currentSegment = max(0, segmentCount - 1)
        }
        isDone = false
        bufferPolls = 0
        playCurrentSegment()
    }

    func skipToNextSegment() {
        player?.stop()
        player = nil
        currentSegment += 1
        if currentSegment >= segmentCount {
            currentLoop += 1
            currentSegment = 0
            if currentLoop >= totalLoops {
                isPlaying = false
                isDone = true
                teardownRemoteCommands()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
        }
        isDone = false
        bufferPolls = 0
        playCurrentSegment()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Parrot] Audio session error: \(error)")
        }
    }

    private func playCurrentSegment() {
        guard currentSegment < segmentCount else {
            advanceLoop()
            return
        }
        // In streaming mode the file for this segment may not be on disk yet.
        // Buffer: poll briefly until it lands, then play. Give up after a ceiling.
        guard let url = urlForSegment(currentSegment) else {
            if streaming && bufferPolls < bufferMaxPolls {
                bufferPolls += 1
                isPlaying = true
                updateNowPlaying()
                DispatchQueue.main.asyncAfter(deadline: .now() + bufferPollInterval) { [weak self] in
                    self?.playCurrentSegment()
                }
            } else {
                advanceSegment()
            }
            return
        }
        bufferPolls = 0
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
            updateNowPlaying()
        } catch {
            print("[Parrot] Playback error segment \(currentSegment): \(error)")
            advanceSegment()
        }
    }

    private func advanceSegment() {
        currentSegment += 1
        bufferPolls = 0
        if currentSegment < segmentCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + segmentPause) { [weak self] in
                self?.playCurrentSegment()
            }
        } else {
            advanceLoop()
        }
    }

    private func advanceLoop() {
        currentLoop += 1
        if currentLoop < totalLoops {
            currentSegment = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.playCurrentSegment()
            }
        } else {
            isPlaying = false
            isDone = true
            teardownRemoteCommands()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        if let phrase = phrase {
            info[MPMediaItemPropertyTitle] = phrase.spanishPhrase
            info[MPMediaItemPropertyArtist] = "Seagull Steven"
            info[MPMediaItemPropertyAlbumTitle] = "Professor Madrid"
        }
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private var commandTargets: [Any] = []

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        commandTargets.append(
            center.playCommand.addTarget { [weak self] _ in
                self?.player?.play()
                self?.isPlaying = true
                self?.updateNowPlaying()
                return .success
            }
        )
        commandTargets.append(
            center.pauseCommand.addTarget { [weak self] _ in
                self?.player?.pause()
                self?.isPlaying = false
                self?.updateNowPlaying()
                return .success
            }
        )
        commandTargets.append(
            center.togglePlayPauseCommand.addTarget { [weak self] _ in
                self?.togglePlayPause()
                return .success
            }
        )
    }

    private func teardownRemoteCommands() {
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        commandTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

extension LoopingParrotPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        advanceSegment()
    }
}
