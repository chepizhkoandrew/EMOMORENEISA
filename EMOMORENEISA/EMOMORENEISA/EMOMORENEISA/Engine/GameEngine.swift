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
    @Published var hideCorrect: Bool = false

    struct LastResult {
        let pronoun: String
        let conjugation: String
        let userTranscript: String
        let correct: Bool
    }

    var timerSeconds: Double = 4.0
    var selectedTense: Tense = .present

    private let postProcessingWindow: Double = 1.5

    private var cellTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?
    private var postProcessTimer: AnyCancellable?
    private var listeningGeneration: Int = 0

    private let picker = VerbPicker()
    private let speech = SpeechService()
    private let gemini = GeminiService()

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
        glog("⚙️ ENGINE", "Playing — \(newRound.cells.count) cells | timer \(timerSeconds)s | post-window \(postProcessingWindow)s")
        startCellTimer()
        startListening()
    }

    private func startCellTimer() {
        timeRemaining = timerSeconds
        cellTimer?.cancel()

        guard let cell = activeCell else { return }
        glog("⚙️ ENGINE", "▶︎ Cell \(activeCellIndex + 1)/\(round?.cells.count ?? 0): [\(cell.pronoun.displayLabel)] [\(cell.verb.infinitive)] → expected \"\(cell.expectedConjugation)\"")

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
        guard let cell = activeCell else { return }
        glog("⏱ TIMER ", "⌛ Expired for \"\(cell.expectedConjugation)\" — opening post-processing window (\(postProcessingWindow)s)")

        isPostProcessing = true
        postProcessTimer?.cancel()
        postProcessTimer = Just(())
            .delay(for: .seconds(postProcessingWindow), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isPostProcessing else { return }
                glog("⏱ TIMER ", "❌ Post-window expired — marking missed (no STT arrived)")
                self.isPostProcessing = false
                self.markActiveCell(correct: false, cellIndex: self.activeCellIndex)
                self.advanceCell()
            }
    }

    func submitAnswer(_ transcribed: String) {
        guard let cell = activeCell else {
            glog("⚙️ ENGINE", "submitAnswer — no active cell, ignoring")
            return
        }

        let cellIndex = activeCellIndex
        cellTimer?.cancel()
        postProcessTimer?.cancel()
        isPostProcessing = false

        glog("⚙️ ENGINE", "STT delivered for \"\(cell.expectedConjugation)\": '\(transcribed)'")

        Task {
            glog("🤖 GEMINI", "→ Sending | expected: \"\(cell.expectedConjugation)\" | got: \"\(transcribed)\"")
            let t0 = Date()

            let correct = await gemini.validate(
                transcribed: transcribed,
                expected: cell.expectedConjugation,
                infinitive: cell.verb.infinitive,
                pronoun: cell.pronoun.displayLabel
            )

            let latency = Date().timeIntervalSince(t0)
            glog("🤖 GEMINI", "← \(correct ? "✅ CORRECT" : "❌ WRONG") | latency \(String(format: "%.3f", latency))s")

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
        stopListening()
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
                self.startListening()
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

    func retryCell(at cellIndex: Int) {
        guard phase == .review,
              let r = round,
              cellIndex < r.cells.count,
              r.cells[cellIndex].state == .missed else { return }

        stopListening()
        reviewActiveCellIndex = cellIndex
        liveTranscript = ""
        lastResult = nil
        isListening = true
        listeningGeneration += 1
        let gen = listeningGeneration

        let cell = r.cells[cellIndex]
        glog("⚙️ ENGINE", "🔄 Retry cell \(cellIndex + 1): [\(cell.pronoun.displayLabel)] [\(cell.verb.infinitive)] → \"\(cell.expectedConjugation)\"")

        speech.startListening(
            contextualStrings: sttHints(for: cell),
            onPartialResult: { [weak self] partial in
                guard let self, self.listeningGeneration == gen else { return }
                self.liveTranscript = partial
            },
            onFinalResult: { [weak self] transcribed in
                guard let self, self.listeningGeneration == gen else {
                    glog("🎙  STT  ", "⚠️ Stale retry result discarded")
                    return
                }
                self.isListening = false
                let capturedIndex = self.reviewActiveCellIndex
                self.reviewActiveCellIndex = nil
                self.liveTranscript = ""
                self.submitRetryAnswer(transcribed, cellIndex: capturedIndex ?? cellIndex)
            }
        )
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
        glog("⚙️ ENGINE", "🔄 Retry STT: expected \"\(cell.expectedConjugation)\" | got '\(transcribed)'")

        Task {
            let correct = await gemini.validate(
                transcribed: transcribed,
                expected: cell.expectedConjugation,
                infinitive: cell.verb.infinitive,
                pronoun: cell.pronoun.displayLabel
            )
            glog("🤖 GEMINI", "🔄 Retry → \(correct ? "✅ CORRECT" : "❌ WRONG")")
            markActiveCell(correct: correct, cellIndex: cellIndex, transcript: transcribed)
        }
    }

    func enterResults() {
        cancelRetry()
        phase = .results
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
        startListening()
    }

    func newRound() {
        cellTimer?.cancel()
        countdownTimer?.cancel()
        postProcessTimer?.cancel()
        stopListening()
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
        let gen = listeningGeneration
        isListening = true
        liveTranscript = ""
        glog("🎙  STT  ", "startListening gen=\(gen)")

        let hints = sttHints(for: activeCell)

        speech.startListening(
            contextualStrings: hints,
            onPartialResult: { [weak self] partial in
                guard let self, self.listeningGeneration == gen else { return }
                self.liveTranscript = partial
            },
            onFinalResult: { [weak self] transcribed in
                guard let self, self.isListening, self.listeningGeneration == gen else {
                    glog("🎙  STT  ", "⚠️ Stale result discarded gen=\(gen) — '\(transcribed)'")
                    return
                }
                self.stopListening()
                self.submitAnswer(transcribed)
            }
        )
    }

    private func sttHints(for cell: GameCell?) -> [String] {
        guard let cell else { return [] }
        return sttHints(for: cell)
    }

    private func sttHints(for cell: GameCell) -> [String] {
        let conj = cell.expectedConjugation
        let pronounForms = cell.pronoun.displayLabel
            .components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var hints = [conj]
        for p in pronounForms {
            hints.append("\(p) \(conj)")
        }
        return hints
    }

    private func stopListening() {
        if isListening {
            glog("🎙  STT  ", "stopListening gen=\(listeningGeneration)")
        }
        isListening = false
        speech.stopListening()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
