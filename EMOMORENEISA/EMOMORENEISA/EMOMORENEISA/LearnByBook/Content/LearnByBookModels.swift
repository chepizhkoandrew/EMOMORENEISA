import Foundation

/// One CEFR-ish tier in the fixed textbook curriculum (Beginner → Proficient).
/// `learnerStage` maps this tier onto the app's own `LearnerStage` enum
/// (StudentProfile.swift) so the tutor-facing level system and this
/// curriculum's levels can be cross-referenced later — the two don't share
/// the same case count (this curriculum has 6 tiers spanning through a C2
/// "Proficient" tier, `LearnerStage` tops out at `.advanced`), so it's a
/// plain string tag rather than the enum itself.
struct LearnByBookLevel: Decodable, Identifiable, Hashable {
    let id: String
    let learnerStage: String
    let labelByLocale: [String: String]

    func label(for language: AppLanguage) -> String {
        labelByLocale[language.rawValue]
            ?? labelByLocale[AppLanguage.english.rawValue]
            ?? labelByLocale.values.first
            ?? ""
    }
}

/// A core word/phrase for the topic — same shape as Say It Better's
/// `PhraseFinderItem` (spanish/englishMeaning/registerNote/exampleSentence
/// all stay in Spanish/English regardless of interface language, matching
/// the app-wide convention) so this planning data drops straight into a real
/// Lesson's `items` array once a topic is fully authored.
struct LearnByBookVocabularyItem: Decodable, Identifiable, Hashable {
    let id: String
    let spanish: String
    let englishMeaning: String
    let registerNote: String
    let exampleSentence: String
}

/// One grammar point this topic teaches. Deliberately narrower than a full
/// `ExplanationChunk` sequence (no `relatedItemId`/highlight spans) — this is
/// still planning-stage data; the real per-topic explanation script gets
/// authored later.
struct LearnByBookGrammarFocus: Decodable, Identifiable, Hashable {
    let id: String
    let titleByLocale: [String: String]
    let explanationByLocale: [String: String]

    func title(for language: AppLanguage) -> String {
        titleByLocale[language.rawValue]
            ?? titleByLocale[AppLanguage.english.rawValue]
            ?? titleByLocale.values.first
            ?? ""
    }

    func explanation(for language: AppLanguage) -> String {
        explanationByLocale[language.rawValue]
            ?? explanationByLocale[AppLanguage.english.rawValue]
            ?? explanationByLocale.values.first
            ?? ""
    }
}

/// One quiz question — always answered by SPEAKING the Spanish aloud, never
/// by tapping or typing. That's this mode's whole differentiator from Say It
/// Better's quiz (multiple choice / fill blank): the point here is making the
/// learner actually produce the phrase. Derived straight from the topic's own
/// vocabulary (see `assemble_topics.py`'s `derive_quiz`), so `targetSpanish`
/// always matches one of the topic's `vocabulary` items.
struct LearnByBookQuizQuestion: Decodable, Identifiable, Hashable {
    let id: String
    let promptByLocale: [String: String]
    let targetSpanish: String
    let acceptedAnswers: [String]

    func prompt(for language: AppLanguage) -> String {
        promptByLocale[language.rawValue]
            ?? promptByLocale[AppLanguage.english.rawValue]
            ?? promptByLocale.values.first
            ?? ""
    }
}

/// One node in the fixed topic curriculum. `sourceLabelEs` preserves the
/// original Spanish label from the reference topic list this was adapted
/// from, purely for authoring traceability — it's never shown to learners.
struct LearnByBookTopic: Decodable, Identifiable, Hashable {
    let id: String
    let order: Int
    let levelId: String
    let titleByLocale: [String: String]
    let sourceLabelEs: String
    let vocabulary: [LearnByBookVocabularyItem]
    let grammarFocus: [LearnByBookGrammarFocus]
    let quiz: [LearnByBookQuizQuestion]

    func title(for language: AppLanguage) -> String {
        titleByLocale[language.rawValue]
            ?? titleByLocale[AppLanguage.english.rawValue]
            ?? titleByLocale.values.first
            ?? ""
    }
}

/// Root document decoded from `learnByBook_topics.json`.
struct LearnByBookCurriculum: Decodable {
    let levels: [LearnByBookLevel]
    let topics: [LearnByBookTopic]
}
