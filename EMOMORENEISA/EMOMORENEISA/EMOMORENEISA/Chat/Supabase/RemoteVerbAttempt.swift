import Foundation

/// Supabase mirror of a `VerbAttempt`. Local SwiftData is the source of
/// truth for the on-device stats screen; this is a best-effort backup/future
/// cross-device-analysis mirror, following the same fire-and-forget pattern
/// as `RemoteMemoryCard`.
struct RemoteVerbAttempt: Codable {
    var id: UUID
    var userId: UUID
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

    enum CodingKeys: String, CodingKey {
        case id
        case userId             = "user_id"
        case roundId            = "round_id"
        case verbInfinitive     = "verb_infinitive"
        case verbType           = "verb_type"
        case pronoun
        case tense
        case expectedConjugation = "expected_conjugation"
        case userTranscript      = "user_transcript"
        case correct
        case isJoker             = "is_joker"
        case createdAt           = "created_at"
    }

    init(attempt: VerbAttempt, userId: UUID) {
        self.id = attempt.id
        self.userId = userId
        self.roundId = attempt.roundId
        self.verbInfinitive = attempt.verbInfinitive
        self.verbType = attempt.verbType
        self.pronoun = attempt.pronoun
        self.tense = attempt.tense
        self.expectedConjugation = attempt.expectedConjugation
        self.userTranscript = attempt.userTranscript
        self.correct = attempt.correct
        self.isJoker = attempt.isJoker
        self.createdAt = attempt.createdAt
    }
}
