import Foundation
import Combine

enum GamePhase: Equatable {
    case idle
    case spinning
    case readyToStart
    case countdown(Int)
    case playing
    case results
}

@MainActor
final class GameEngine: ObservableObject {
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var round: Round?
    @Published private(set) var activeCellIndex: Int = 0
    @Published private(set) var timeRemaining: Double = 0
    @Published private(set) var isListening: Bool = false
    @Published private(set) var selectedVerbs: [Verb] = []

    var timerSeconds: Double = 2.0
    var selectedTense: Tense = .present

    private var cellTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?

    private let picker = VerbPicker()
    private let speech = SpeechService()
    private let gemini = GeminiService()

    var activeCell: GameCell? {
        guard let round, activeCellIndex < round.cells.count else { return nil }
        return round.cells[activeCellIndex]
    }

    func startSpin() {
        phase = .spinning
        selectedVerbs = picker.pick()
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
        startCellTimer()
        startListening()
    }

    private func startCellTimer() {
        timeRemaining = timerSeconds
        cellTimer?.cancel()

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
        markActiveCell(correct: false)
        advanceCell()
    }

    func submitAnswer(_ transcribed: String) {
        guard let cell = activeCell else { return }
        cellTimer?.cancel()

        Task {
            let correct = await gemini.validate(
                transcribed: transcribed,
                expected: cell.expectedConjugation,
                infinitive: cell.verb.infinitive,
                pronoun: cell.pronoun.displayLabel
            )
            markActiveCell(correct: correct)
            advanceCell()
        }
    }

    private func markActiveCell(correct: Bool) {
        guard var r = round, activeCellIndex < r.cells.count else { return }
        r.cells[activeCellIndex].state = correct ? .correct : .missed
        r.cells[activeCellIndex].revealed = true
        round = r
    }

    private func advanceCell() {
        stopListening()
        guard let r = round else { return }
        let next = activeCellIndex + 1
        if next < r.cells.count {
            activeCellIndex = next
            startCellTimer()
            startListening()
        } else {
            phase = .results
        }
    }

    private func startListening() {
        isListening = true
        speech.startListening { [weak self] transcribed in
            guard let self, self.isListening else { return }
            self.stopListening()
            self.submitAnswer(transcribed)
        }
    }

    private func stopListening() {
        isListening = false
        speech.stopListening()
    }

    func retryMissed() {
        guard let r = round, !r.missedCells.isEmpty else { return }
        let retry = r.retryRound()
        round = retry
        activeCellIndex = 0
        phase = .playing
        startCellTimer()
        startListening()
    }

    func newRound() {
        cellTimer?.cancel()
        countdownTimer?.cancel()
        stopListening()
        round = nil
        selectedVerbs = []
        phase = .idle
    }
}
