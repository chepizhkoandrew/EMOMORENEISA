import Foundation

enum CellState {
    case pending
    case active
    case correct
    case missed
}

struct GameCell: Identifiable {
    let id = UUID()
    let pronoun: Pronoun
    let verb: Verb
    let tense: Tense
    var state: CellState = .pending
    var revealed: Bool = false
    var userTranscript: String? = nil

    var expectedConjugation: String {
        verb.conjugation(for: pronoun, tense: tense)
    }
}
