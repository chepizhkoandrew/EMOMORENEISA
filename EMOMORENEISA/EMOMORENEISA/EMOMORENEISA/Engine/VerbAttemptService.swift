import Foundation
import SwiftData

/// Persists verb-game word attempts and mirrors them to Supabase. Mirrors
/// `MemoryCardService`'s local-write + fire-and-forget-remote-mirror pattern.
struct VerbAttemptService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(
        roundId: UUID,
        verb: Verb,
        pronoun: Pronoun,
        tense: Tense,
        expectedConjugation: String,
        userTranscript: String,
        correct: Bool
    ) {
        let attempt = VerbAttempt(
            roundId: roundId,
            verbInfinitive: verb.infinitive,
            verbType: verb.type.rawValue,
            pronoun: pronoun.rawValue,
            tense: tense.rawValue,
            expectedConjugation: expectedConjugation,
            userTranscript: userTranscript,
            correct: correct,
            isJoker: verb.joker
        )
        context.insert(attempt)
        try? context.save()

        if let userId = AuthState.shared.userId {
            let snapshot = RemoteVerbAttempt(attempt: attempt, userId: userId)
            Task.detached {
                await SupabaseSyncService.shared.upsertVerbAttempt(snapshot)
            }
        }
    }
}
