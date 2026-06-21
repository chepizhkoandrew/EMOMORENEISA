import AVFoundation
import Observation

@Observable
final class TTSService: NSObject {
    static let shared = TTSService()

    var playingMessageId: UUID? = nil
    var loadingMessageId: UUID? = nil
    var isQueueActive: Bool = false
    var isLoading: Bool = false
    var isPaused: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var queue: [(id: UUID, text: String)] = []
    private var queueIndex: Int = 0
    private var progressTimer: Timer?

    // Chunk state — all indexed by chunk index
    private var activeChunks: [String] = []           // text per chunk
    private var chunkTasks: [Task<URL?, Never>] = []  // one parallel fetch task per chunk
    private var chunkURLs: [URL?] = []                // nil until that chunk's task finishes
    private var chunkDurations: [TimeInterval?] = []  // nil until known; estimate until then
    private var currentChunkIndex: Int = 0
    private var completedChunksDuration: TimeInterval = 0
    private var durationMonitorTask: Task<Void, Never>? = nil

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("esp-tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private override init() { super.init() }

    // MARK: - Public API

    func speak(text: String, messageId: UUID) {
        clearQueue()
        Task { await playSingle(text: text, messageId: messageId) }
    }

    func speakQueue(startingFrom messageId: UUID, in messages: [(id: UUID, text: String)]) {
        let startIdx = messages.firstIndex(where: { $0.id == messageId }) ?? 0
        let items = Array(messages[startIdx...])
        guard !items.isEmpty else { return }
        clearQueue()
        queue = items
        queueIndex = 0
        isQueueActive = true
        Task { await playCurrentQueueItem() }
    }

    func toggleQueue(startingFrom messageId: UUID, in messages: [(id: UUID, text: String)]) {
        if isQueueActive || playingMessageId != nil {
            stop()
        } else {
            speakQueue(startingFrom: messageId, in: messages)
        }
    }

    func stop() {
        cancelChunkWork()
        player?.stop()
        player = nil
        clearQueue()
    }

    func togglePause() {
        guard let player else { return }
        if isPaused {
            player.play()
            isPaused = false
            startProgressTimer()
        } else {
            player.pause()
            isPaused = true
            stopProgressTimer()
        }
    }

    func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration))
        var accumulated: TimeInterval = 0
        for i in 0..<activeChunks.count {
            guard let dur = chunkDurations[i] else { break }
            let end = accumulated + dur
            if target <= end || i == activeChunks.count - 1 {
                let localTime = target - accumulated
                if i == currentChunkIndex, let player {
                    player.currentTime = max(0, min(localTime, dur))
                    currentTime = accumulated + player.currentTime
                } else if chunkURLs[i] != nil {
                    Task { @MainActor in await self.jumpToChunk(i, localTime: max(0, localTime)) }
                }
                return
            }
            accumulated = end
        }
    }

    // MARK: - Private State

    private func cancelChunkWork() {
        chunkTasks.forEach { $0.cancel() }
        chunkTasks = []
        durationMonitorTask?.cancel()
        durationMonitorTask = nil
    }

    private func clearQueue() {
        cancelChunkWork()
        activeChunks = []
        chunkURLs = []
        chunkDurations = []
        currentChunkIndex = 0
        completedChunksDuration = 0
        queue = []
        queueIndex = 0
        isQueueActive = false
        playingMessageId = nil
        loadingMessageId = nil
        isLoading = false
        isPaused = false
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = self.completedChunksDuration + player.currentTime
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Duration Estimate

    private func updateDurationEstimate() {
        let known = chunkDurations.compactMap { $0 }
        guard !known.isEmpty else { return }
        let knownTotal = known.reduce(0, +)
        if known.count == activeChunks.count {
            duration = knownTotal
        } else {
            duration = knownTotal / Double(known.count) * Double(activeChunks.count)
        }
    }

    // MARK: - Cache

    private func cachedChunkURL(for messageId: UUID, chunkIndex: Int) -> URL? {
        for ext in ["aac", "m4a", "wav", "mp3"] {
            let url = cacheDir.appendingPathComponent("\(messageId.uuidString)-c\(chunkIndex).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func cacheChunkURL(for messageId: UUID, chunkIndex: Int, ext: String) -> URL {
        cacheDir.appendingPathComponent("\(messageId.uuidString)-c\(chunkIndex).\(ext)")
    }

    // MARK: - Text Splitting

    private func sentenceBoundary(in text: String, after minOffset: Int) -> String.Index? {
        guard text.count > minOffset else { return nil }
        var idx = text.index(text.startIndex, offsetBy: minOffset)
        while idx < text.endIndex {
            let ch = text[idx]
            let next = text.index(after: idx)
            if ".!?".contains(ch) && (next == text.endIndex || text[next] == " " || text[next] == "\n") {
                return next
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private func splitTextIntoChunks(_ text: String) -> [String] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 60 else { return [t] }

        guard let s1 = sentenceBoundary(in: t, after: 40) else { return [t] }
        let c1 = String(t[..<s1]).trimmingCharacters(in: .whitespaces)
        let rest1 = s1 < t.endIndex ? String(t[s1...]).trimmingCharacters(in: .whitespaces) : ""
        guard !rest1.isEmpty else { return [c1] }

        guard let s2 = sentenceBoundary(in: rest1, after: 30) else { return [c1, rest1] }
        let c2 = String(rest1[..<s2]).trimmingCharacters(in: .whitespaces)
        let c3 = s2 < rest1.endIndex ? String(rest1[s2...]).trimmingCharacters(in: .whitespaces) : ""

        return [c1, c2, c3].filter { !$0.isEmpty }
    }

    // MARK: - Playback

    @MainActor
    private func playSingle(text: String, messageId: UUID) async {
        let chunks = splitTextIntoChunks(text)
        activeChunks = chunks
        chunkURLs = Array(repeating: nil, count: chunks.count)
        chunkDurations = Array(repeating: nil, count: chunks.count)
        currentChunkIndex = 0
        completedChunksDuration = 0
        cancelChunkWork()

        // Start ALL chunk fetches in parallel so later chunks are ready
        // before the earlier ones finish playing — eliminating inter-chunk pauses.
        for (i, chunkText) in chunks.enumerated() {
            let idx = i
            let msgId = messageId
            let task = Task<URL?, Never> {
                if let cached = self.cachedChunkURL(for: msgId, chunkIndex: idx) { return cached }
                guard let (data, ext) = await self.fetchTTS(text: chunkText) else { return nil }
                let fileURL = self.cacheChunkURL(for: msgId, chunkIndex: idx, ext: ext)
                try? data.write(to: fileURL)
                return fileURL
            }
            chunkTasks.append(task)
        }

        // Monitor chunks 1+ in background: store their URLs and pre-read durations
        // so the main delegate has zero wait when advancing to the next chunk.
        let tasksSnapshot = chunkTasks
        durationMonitorTask = Task { @MainActor [weak self] in
            for i in 1..<tasksSnapshot.count {
                guard !Task.isCancelled else { break }
                if let url = await tasksSnapshot[i].value {
                    guard let self, !Task.isCancelled else { break }
                    self.chunkURLs[i] = url
                    if let p = try? AVAudioPlayer(contentsOf: url), self.chunkDurations[i] == nil {
                        self.chunkDurations[i] = p.duration
                        self.updateDurationEstimate()
                    }
                }
            }
        }

        // Wait for chunk 0 (the only blocking wait the user ever experiences)
        isLoading = true
        loadingMessageId = messageId

        guard let url0 = await chunkTasks[0].value else {
            isLoading = false
            loadingMessageId = nil
            playingMessageId = nil
            return
        }

        chunkURLs[0] = url0
        isLoading = false
        loadingMessageId = nil
        await playChunk(at: 0, messageId: messageId)
    }

    @MainActor
    private func playChunk(at index: Int, messageId: UUID) async {
        guard index < chunkURLs.count, let url = chunkURLs[index] else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            currentChunkIndex = index
            playingMessageId = messageId
            isPaused = false
            currentTime = completedChunksDuration

            if chunkDurations[index] == nil {
                chunkDurations[index] = p.duration
            }
            updateDurationEstimate()
            startProgressTimer()
        } catch {
            print("[TTS] Chunk \(index) error: \(error)")
            playingMessageId = nil
        }
    }

    @MainActor
    private func jumpToChunk(_ index: Int, localTime: TimeInterval) async {
        player?.stop()
        guard index < chunkURLs.count, let url = chunkURLs[index], let msgId = playingMessageId else { return }
        completedChunksDuration = (0..<index).compactMap { chunkDurations[$0] }.reduce(0, +)
        currentChunkIndex = index

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.currentTime = localTime
            p.play()
            player = p
            isPaused = false
            currentTime = completedChunksDuration + p.currentTime
            startProgressTimer()
            _ = msgId
        } catch {
            print("[TTS] Jump chunk \(index) error: \(error)")
        }
    }

    @MainActor
    private func playCurrentQueueItem() async {
        guard isQueueActive, queueIndex < queue.count else {
            isQueueActive = false
            playingMessageId = nil
            return
        }
        let item = queue[queueIndex]
        await playSingle(text: item.text, messageId: item.id)
    }

    private func finishCurrentMessagePlayback() {
        currentTime = 0
        duration = 0
        isPaused = false
        if isQueueActive {
            queueIndex += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                await playCurrentQueueItem()
            }
        } else {
            playingMessageId = nil
        }
    }

    // MARK: - TTS Fetch

    private func fetchTTS(text: String) async -> (Data, String)? {
        do {
            let (raw, mime) = try await ProxyClient.shared.tts(text: text)
            let m = mime.lowercased()
            // AAC (and m4a) play natively via AVAudioPlayer — store as-is. Only raw
            // PCM needs the WAV header.
            if m.hasPrefix("audio/aac") { return (raw, "aac") }
            if m.hasPrefix("audio/mp4") || m.hasPrefix("audio/m4a") || m.hasPrefix("audio/x-m4a") { return (raw, "m4a") }
            return (audioDataToWAV(raw, mimeType: mime), "wav")
        } catch {
            print("[TTS] proxy TTS failed: \(error)")
            return nil
        }
    }

    // MARK: - PCM → WAV

    private func audioDataToWAV(_ rawData: Data, mimeType: String) -> Data {
        if mimeType.hasPrefix("audio/wav") || mimeType.hasPrefix("audio/wave") { return rawData }
        let sampleRate: UInt32
        if let rateStr = mimeType.components(separatedBy: "rate=").last?.trimmingCharacters(in: .whitespaces),
           let rate = UInt32(rateStr) {
            sampleRate = rate
        } else {
            sampleRate = 24000
        }
        return wrapPCMInWAV(pcmData: rawData, sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
    }

    private func wrapPCMInWAV(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let dataSize = UInt32(pcmData.count)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        var h = Data()
        func u32(_ v: UInt32) { h.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        func u16(_ v: UInt16) { h.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Array($0) }) }
        h.append(contentsOf: "RIFF".utf8); u32(36 + dataSize)
        h.append(contentsOf: "WAVE".utf8)
        h.append(contentsOf: "fmt ".utf8); u32(16)
        u16(1); u16(channels); u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bitsPerSample)
        h.append(contentsOf: "data".utf8); u32(dataSize)
        return h + pcmData
    }
}

// MARK: - AVAudioPlayerDelegate

extension TTSService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        stopProgressTimer()

        if let dur = chunkDurations[currentChunkIndex] {
            completedChunksDuration += dur
        }
        currentTime = completedChunksDuration

        let nextIndex = currentChunkIndex + 1

        guard nextIndex < activeChunks.count, let msgId = playingMessageId else {
            finishCurrentMessagePlayback()
            return
        }

        if chunkURLs[nextIndex] != nil {
            // Already fetched by the monitor task — zero wait, play immediately
            Task { @MainActor in await self.playChunk(at: nextIndex, messageId: msgId) }
        } else {
            // Still in flight (rare with parallel fetching) — await the task
            guard nextIndex < chunkTasks.count else { finishCurrentMessagePlayback(); return }
            let task = chunkTasks[nextIndex]
            Task { @MainActor in
                if let url = await task.value {
                    self.chunkURLs[nextIndex] = url
                    if let p = try? AVAudioPlayer(contentsOf: url), self.chunkDurations[nextIndex] == nil {
                        self.chunkDurations[nextIndex] = p.duration
                        self.updateDurationEstimate()
                    }
                    await self.playChunk(at: nextIndex, messageId: msgId)
                } else {
                    self.finishCurrentMessagePlayback()
                }
            }
        }
    }
}
