import Foundation

enum Tense: String, CaseIterable, Identifiable {
    case present = "Present"
    case preterite = "Preterite"
    case imperfect = "Imperfect"
    case future = "Future"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .present: return "Presente"
        case .preterite: return "Pretérito"
        case .imperfect: return "Imperfecto"
        case .future: return "Futuro"
        }
    }
}

struct Round {
    /// Shared by every `VerbAttempt` recorded during this round — lets stats
    /// count "games played" as distinct round ids, including rounds the user
    /// abandons partway through.
    let id: UUID
    let verbs: [Verb]
    let tense: Tense
    var cells: [GameCell]
    let timerSeconds: Double

    var correctCells: [GameCell] { cells.filter { $0.state == .correct } }
    var missedCells: [GameCell] { cells.filter { $0.state == .missed } }

    static func make(verbs: [Verb], tense: Tense, timerSeconds: Double) -> Round {
        var cells: [GameCell] = []
        for pronoun in Pronoun.allCases {
            for verb in verbs {
                cells.append(GameCell(pronoun: pronoun, verb: verb, tense: tense))
            }
        }
        cells.shuffle()
        return Round(id: UUID(), verbs: verbs, tense: tense, cells: cells, timerSeconds: timerSeconds)
    }

    func retryRound() -> Round {
        var retryCells = missedCells.map { cell -> GameCell in
            var c = cell
            c.state = .pending
            c.revealed = false
            return c
        }
        retryCells.shuffle()
        // A fresh round id: retrying missed cells is its own "game played" —
        // consistent with `repeatRound()`/`startPlaying()` also minting a
        // new id for every new Round.
        return Round(id: UUID(), verbs: verbs, tense: tense, cells: retryCells, timerSeconds: timerSeconds)
    }
}
