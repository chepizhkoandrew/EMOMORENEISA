import Foundation

enum Tense: String, CaseIterable, Identifiable {
    case present = "Present"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .present: return "Presente"
        }
    }
}

struct Round {
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
                cells.append(GameCell(pronoun: pronoun, verb: verb))
            }
        }
        cells.shuffle()
        return Round(verbs: verbs, tense: tense, cells: cells, timerSeconds: timerSeconds)
    }

    func retryRound() -> Round {
        var retryCells = missedCells.map { cell -> GameCell in
            var c = cell
            c.state = .pending
            c.revealed = false
            return c
        }
        retryCells.shuffle()
        return Round(verbs: verbs, tense: tense, cells: retryCells, timerSeconds: timerSeconds)
    }
}
