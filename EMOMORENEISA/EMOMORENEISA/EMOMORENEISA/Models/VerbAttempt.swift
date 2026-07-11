import Foundation
import SwiftData

/// One word attempt in the verb-conjugation game — written the moment a cell
/// is marked correct/missed (`GameEngine.markActiveCell`), not batched at
/// round completion. This is deliberate: a user can back out mid-round (the
/// GameMatrixView "STOP" button calls `engine.newRound()` directly, bypassing
/// `ResultsView` entirely), so this is the only hook guaranteed to fire for
/// every word regardless of whether the round is ever finished.
@Model
final class VerbAttempt {
    @Attribute(.unique) var id: UUID
    /// Shared by every attempt within one round — lets stats count "games
    /// played" as distinct round ids, including partial/abandoned rounds.
    var roundId: UUID
    var verbInfinitive: String
    var verbType: String
    var pronoun: String
    var tense: String
    var expectedConjugation: String
    var userTranscript: String
    var correct: Bool
    var isJoker: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        roundId: UUID,
        verbInfinitive: String,
        verbType: String,
        pronoun: String,
        tense: String,
        expectedConjugation: String,
        userTranscript: String,
        correct: Bool,
        isJoker: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.roundId = roundId
        self.verbInfinitive = verbInfinitive
        self.verbType = verbType
        self.pronoun = pronoun
        self.tense = tense
        self.expectedConjugation = expectedConjugation
        self.userTranscript = userTranscript
        self.correct = correct
        self.isJoker = isJoker
        self.createdAt = createdAt
    }
}
