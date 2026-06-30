import Foundation
import Combine

enum GamePhase: Equatable {
    case idle
    case spinning
    case readyToStart
    case countdown(Int)
    case playing
    case review
    case results
}

@MainActor
final class GameEngine: ObservableObject {
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var round: Round?
    @Published private(set) var activeCellIndex: Int = 0
    @Published private(set) var timeRemaining: Double = 0
    @Published private(set) var isListening: Bool = false
    @Published private(set) var isPostProcessing: Bool = false
    @Published private(set) var selectedVerbs: [Verb] = []
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var lastResult: LastResult? = nil
    @Published private(set) var reviewActiveCellIndex: Int? = nil
    @Published private(set) var isPaused: Bool = false
    @Published var hideCorrect: Bool = false

    struct LastResult {
        let pronoun: String
        let conjugation: String
        let userTranscript: String
        let correct: Bool
    }

    @Published var timerSeconds: Double = 4.0
    var selectedTense: Tense = .present

    private var cellTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?
    private var retryTimer: AnyCancellable?
    private var listeningGeneration: Int = 0

    private let picker = VerbPicker()
    private let audioRecorder = AudioRecorder()

    var activeCell: GameCell? {
        guard let round, activeCellIndex < round.cells.count else { return nil }
        return round.cells[activeCellIndex]
    }

    var currentActiveCell: GameCell? {
        switch phase {
        case .playing:
            return activeCell
        case .review:
            guard let idx = reviewActiveCellIndex, let r = round, idx < r.cells.count else { return nil }
            return r.cells[idx]
        default:
            return nil
        }
    }

    func startSpin() {
        phase = .spinning
        selectedVerbs = picker.pick()
        glog("⚙️ ENGINE", "Round started — verbs: \(selectedVerbs.map(\.infinitive).joined(separator: ", "))")
    }

    func onSpinComplete() {
        phase = .readyToStart
    }

    func reSpin() {
        cellTimer?.cancel()
        countdownTimer?.cancel()
        stopListening()
        selectedVerbs = picker.pick()
        phase = .spinning
        glog("⚙️ ENGINE", "Re-spin — verbs: \(selectedVerbs.map(\.infinitive).joined(separator: ", "))")
    }

    func beginCountdown() {
        var count = 3
        phase = .countdown(count)

        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                count -= 1
                if count > 0 {
                    self.phase = .countdown(count)
                } else {
                    self.countdownTimer = nil
                    self.startPlaying()
                }
            }
    }

    private func startPlaying() {
        let newRound = Round.make(
            verbs: selectedVerbs,
            tense: selectedTense,
            timerSeconds: timerSeconds
        )
        round = newRound
        activeCellIndex = 0
        phase = .playing
        glog("⚙️ ENGINE", "Playing — \(newRound.cells.count) cells | timer \(timerSeconds)s")
        startCellTimer()
    }

    private func startCellTimer() {
        timeRemaining = timerSeconds
        cellTimer?.cancel()

        guard let cell = activeCell else { return }
        glog("⚙️ ENGINE", "▶︎ Cell \(activeCellIndex + 1)/\(round?.cells.count ?? 0): [\(cell.pronoun.displayLabel)] [\(cell.verb.infinitive)] → expected \"\(cell.expectedConjugation)\"")

        startListening()

        cellTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.timeRemaining -= 0.05
                if self.timeRemaining <= 0 {
                    self.cellTimedOut()
                }
            }
    }

    private func cellTimedOut() {
        cellTimer?.cancel()
        guard activeCell != nil else { return }
        glog("⏱ TIMER ", "⌛ Expired — stopping recording, transcribing via proxy")

        isListening = false
        isPostProcessing = true
        let cellIndex = activeCellIndex

        Task {
            let transcribed = await audioRecorder.stopAndTranscribe()
            guard self.isPostProcessing else { return }
            self.isPostProcessing = false
            glog("⏱ TIMER ", "✅ Proxy transcript: '\(transcribed)'")
            self.submitAnswer(transcribed, atCellIndex: cellIndex)
        }
    }

    private func submitAnswer(_ transcribed: String, atCellIndex cellIndex: Int) {
        guard let r = round, cellIndex < r.cells.count else {
            glog("⚙️ ENGINE", "submitAnswer — invalid cell index \(cellIndex), ignoring")
            return
        }

        let cell = r.cells[cellIndex]
        glog("⚙️ ENGINE", "STT delivered for \"\(cell.expectedConjugation)\": '\(transcribed)'")

        let normalized = normalizeTranscript(transcribed)
        if normalized != transcribed {
            glog("⚙️ ENGINE", "Normalized transcript: '\(transcribed)' → '\(normalized)'")
        }

        let normalizedExpected = normalizeTranscript(cell.expectedConjugation)
        if normalized == normalizedExpected && !normalized.isEmpty {
            glog("⚙️ ENGINE", "✅ Exact match '\(normalized)' == '\(normalizedExpected)' — skipping server")
            markActiveCell(correct: true, cellIndex: cellIndex, transcript: transcribed)
            advanceCell()
            return
        }

        Task {
            glog("🤖 SERVER", "→ verb-check | expected: \"\(cell.expectedConjugation)\" | got: \"\(normalized)\"")
            let t0 = Date()

            let correct: Bool
            do {
                correct = try await ProxyClient.shared.verbCheck(
                    transcript: normalized,
                    expected: cell.expectedConjugation,
                    infinitive: cell.verb.infinitive,
                    pronoun: cell.pronoun.displayLabel
                )
            } catch {
                glog("🤖 SERVER", "⚠️ verb-check failed (\(error.localizedDescription)) — fallback local")
                correct = localFallback(transcribed: normalized, expected: cell.expectedConjugation)
            }

            let latency = Date().timeIntervalSince(t0)
            glog("🤖 SERVER", "← \(correct ? "✅ CORRECT" : "❌ WRONG") | latency \(String(format: "%.3f", latency))s")

            markActiveCell(correct: correct, cellIndex: cellIndex, transcript: transcribed)
            advanceCell()
        }
    }

    private func markActiveCell(correct: Bool, cellIndex: Int, transcript: String = "") {
        guard var r = round, cellIndex < r.cells.count else { return }
        r.cells[cellIndex].state = correct ? .correct : .missed
        r.cells[cellIndex].revealed = true
        if !transcript.isEmpty {
            r.cells[cellIndex].userTranscript = transcript
        }
        round = r
        lastResult = LastResult(
            pronoun: r.cells[cellIndex].pronoun.displayLabel,
            conjugation: r.cells[cellIndex].expectedConjugation,
            userTranscript: transcript,
            correct: correct
        )
        glog("⚙️ ENGINE", "Cell \(cellIndex + 1) → \(correct ? "✅ correct" : "❌ missed") | heard: '\(transcript)'")
    }

    private func advanceCell() {
        guard let r = round else { return }
        let next = activeCellIndex + 1

        activeCellIndex = r.cells.count
        timeRemaining = 0
        liveTranscript = ""

        if next < r.cells.count {
            glog("⚙️ ENGINE", "⏸ 1s pause before cell \(next + 1)/\(r.cells.count)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.phase == .playing else { return }
                self.lastResult = nil
                self.activeCellIndex = next
                self.startCellTimer()
            }
        } else {
            let correct = r.cells.filter { $0.state == .correct }.count
            let missed  = r.cells.filter { $0.state == .missed }.count
            glog("⚙️ ENGINE", "🏁 Round done — correct: \(correct) | missed: \(missed)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.phase = .review
            }
        }
    }

    // MARK: - Review mode

    private let retryRecordingSeconds: Double = 5.0

    func retryCell(at cellIndex: Int) {
        guard phase == .review,
              let r = round,
              cellIndex < r.cells.count,
              r.cells[cellIndex].state == .missed else { return }

        stopListening()
        reviewActiveCellIndex = cellIndex
        liveTranscript = ""
        lastResult = nil
        listeningGeneration += 1
        let gen = listeningGeneration

        let cell = r.cells[cellIndex]
        glog("⚙️ ENGINE", "🔄 Retry cell \(cellIndex + 1): [\(cell.pronoun.displayLabel)] [\(cell.verb.infinitive)] → \"\(cell.expectedConjugation)\"")

        do {
            try audioRecorder.start()
            isListening = true
        } catch {
            glog("🎙  STT  ", "⚠️ AudioRecorder start failed for retry: \(error)")
            return
        }

        retryTimer?.cancel()
        retryTimer = Just(())
            .delay(for: .seconds(retryRecordingSeconds), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.listeningGeneration == gen else { return }
                self.deliverRetry(cellIndex: cellIndex, gen: gen)
            }
    }

    private func deliverRetry(cellIndex: Int, gen: Int) {
        guard listeningGeneration == gen else { return }
        isListening = false
        retryTimer?.cancel()
        let capturedCellIndex = reviewActiveCellIndex ?? cellIndex
        reviewActiveCellIndex = nil
        liveTranscript = ""

        Task {
            let transcribed = await audioRecorder.stopAndTranscribe()
            glog("⚙️ ENGINE", "🔄 Retry transcript: '\(transcribed)'")
            self.submitRetryAnswer(transcribed, cellIndex: capturedCellIndex)
        }
    }

    func cancelRetry() {
        guard reviewActiveCellIndex != nil else { return }
        stopListening()
        reviewActiveCellIndex = nil
        liveTranscript = ""
        glog("⚙️ ENGINE", "🔄 Retry cancelled")
    }

    private func submitRetryAnswer(_ transcribed: String, cellIndex: Int) {
        guard let cell = round?.cells[safe: cellIndex] else { return }
        let normalized = normalizeTranscript(transcribed)
        let normalizedExpected = normalizeTranscript(cell.expectedConjugation)
        glog("⚙️ ENGINE", "🔄 Retry STT: expected \"\(cell.expectedConjugation)\" | got '\(normalized)'")

        if normalized == normalizedExpected && !normalized.isEmpty {
            glog("⚙️ ENGINE", "✅ Retry exact match — skipping server")
            markActiveCell(correct: true, cellIndex: cellIndex, transcript: transcribed)
            return
        }

        Task {
            let correct: Bool
            do {
                correct = try await ProxyClient.shared.verbCheck(
                    transcript: normalized,
                    expected: cell.expectedConjugation,
                    infinitive: cell.verb.infinitive,
                    pronoun: cell.pronoun.displayLabel
                )
            } catch {
                glog("🤖 SERVER", "⚠️ Retry verb-check failed — fallback local")
                correct = localFallback(transcribed: normalized, expected: cell.expectedConjugation)
            }
            glog("🤖 SERVER", "🔄 Retry → \(correct ? "✅ CORRECT" : "❌ WRONG")")
            markActiveCell(correct: correct, cellIndex: cellIndex, transcript: transcribed)
        }
    }

    func enterResults() {
        cancelRetry()
        phase = .results
    }

    func repeatRound() {
        cellTimer?.cancel()
        retryTimer?.cancel()
        stopListening()
        isPaused = false
        isPostProcessing = false
        lastResult = nil
        reviewActiveCellIndex = nil
        hideCorrect = false
        startPlaying()
    }

    // MARK: - Legacy retry (keeps ResultsView working)
    func retryMissed() {
        guard let r = round, !r.missedCells.isEmpty else { return }
        let retry = r.retryRound()
        round = retry
        activeCellIndex = 0
        hideCorrect = false
        reviewActiveCellIndex = nil
        phase = .playing
        glog("⚙️ ENGINE", "Retry — \(retry.cells.count) missed cells")
        startCellTimer()
    }

    func pause() {
        guard phase == .playing, !isPaused else { return }
        isPaused = true
        cellTimer?.cancel()
        cellTimer = nil
        stopListening()
        glog("⚙️ ENGINE", "⏸ Paused — timeRemaining: \(String(format: "%.2f", timeRemaining))s")
    }

    func resume() {
        guard phase == .playing, isPaused else { return }
        isPaused = false
        glog("⚙️ ENGINE", "▶︎ Resumed — timeRemaining: \(String(format: "%.2f", timeRemaining))s")
        startListening()
        cellTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.timeRemaining -= 0.05
                if self.timeRemaining <= 0 {
                    self.cellTimedOut()
                }
            }
    }

    func adjustTimer(by delta: Double) {
        timerSeconds = max(2.0, min(12.0, timerSeconds + delta))
        glog("⚙️ ENGINE", "⏱ Timer adjusted to \(String(format: "%.1f", timerSeconds))s")
    }

    func newRound() {
        cellTimer?.cancel()
        countdownTimer?.cancel()
        retryTimer?.cancel()
        stopListening()
        isPaused = false
        isPostProcessing = false
        lastResult = nil
        reviewActiveCellIndex = nil
        hideCorrect = false
        round = nil
        selectedVerbs = []
        phase = .idle
        glog("⚙️ ENGINE", "Reset → idle")
    }

    private func startListening() {
        listeningGeneration += 1
        isListening = true
        liveTranscript = ""
        glog("🎙  STT  ", "Start recording gen=\(listeningGeneration)")
        do {
            try audioRecorder.start()
        } catch {
            glog("🎙  STT  ", "⚠️ AudioRecorder start failed: \(error)")
            isListening = false
        }
    }

    private func stopListening() {
        if isListening {
            glog("🎙  STT  ", "stopListening gen=\(listeningGeneration)")
        }
        isListening = false
        retryTimer?.cancel()
        audioRecorder.cancel()
    }

    private func normalizeTranscript(_ s: String) -> String {
        let punctuation = CharacterSet(charactersIn: ".,!?¿¡;:\"'()[]")
        return s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: punctuation)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localFallback(transcribed: String, expected: String) -> Bool {
        let normalize: (String) -> String = {
            $0.lowercased()
              .folding(options: .diacriticInsensitive, locale: .current)
              .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let a = normalize(transcribed)
        let b = normalize(expected)
        if a == b || a.hasSuffix(b) || b.hasSuffix(a) { return true }
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        let sim = maxLen == 0 ? 1.0 : 1.0 - Double(dist) / Double(maxLen)
        return sim >= (b.count <= 5 ? 0.75 : 0.82)
    }

    private func levenshtein(_ s: String, _ t: String) -> Int {
        let s = Array(s), t = Array(t)
        let m = s.count, n = t.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = s[i-1] == t[j-1] ? dp[i-1][j-1] : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
