import Foundation

enum ChapterKind: String, Decodable {
    case phraseFinder
    case wordSwap
}

enum QuestionType: String, Decodable {
    case multipleChoice
    case fillBlank
    /// Reserved for a future "say it aloud" STT question type, reusing the
    /// Try-it feedback state machine already designed for it. Not built yet —
    /// no view handles this case in v1.
    case sayItAloud
}

struct Lesson: Decodable {
    let id: String
    let titleByLocale: [String: String]
    /// Explicit author-controlled display order in the lesson list — plain
    /// dictionary/alphabetical ordering isn't reliable once there's more
    /// than one lesson.
    let order: Int
    let chapters: [Chapter]

    /// Falls back to English, then to whatever's present, matching
    /// `ExplanationChunk.text(for:)`'s convention — the Ukrainian phrasing is
    /// its own sentence ("Кажи замість: ..."), not a word-for-word
    /// translation of the English "Say It Better: ...".
    func title(for language: AppLanguage) -> String {
        titleByLocale[language.rawValue]
            ?? titleByLocale[AppLanguage.english.rawValue]
            ?? titleByLocale.values.first
            ?? ""
    }
}

struct Chapter: Decodable {
    let id: String
    let kind: ChapterKind
    let explanation: [ExplanationChunk]
    let items: [PhraseFinderItem]
    let quiz: [QuizQuestion]
    /// Populated only for `.wordSwap` chapters (not authored/used in v1's
    /// single "goodbye" Phrase Finder chapter — the shape exists now so the
    /// `kind` discriminator has somewhere to route to later).
    let wordSwapItems: [WordSwapItem]?
}

/// One of Madrid's pre-written, pre-recorded autoplay bubbles. `text`
/// speaks in the learner's own interface language (English/Ukrainian) about
/// the Spanish phrase being taught — not in Spanish itself.
struct ExplanationChunk: Decodable {
    let id: String
    let textByLocale: [String: String]
    let relatedItemId: String?
    /// Author-specified substrings of this chunk's text — the Spanish
    /// phrase(s) being taught plus the general "what this is about" phrase
    /// (e.g. "five real ways to say goodbye") — that should render in the
    /// bubble's accent color so the key vocabulary/topic stands out from the
    /// surrounding narration. Explicit per-locale list rather than computed
    /// at runtime, since guessing "which substrings matter" from raw text is
    /// exactly the kind of thing that silently mis-highlights partial words.
    let highlightsByLocale: [String: [String]]?

    /// Falls back to English, then to whatever's present, so a lesson never
    /// renders empty just because one locale's copy is missing.
    func text(for language: AppLanguage) -> String {
        textByLocale[language.rawValue]
            ?? textByLocale[AppLanguage.english.rawValue]
            ?? textByLocale.values.first
            ?? ""
    }

    func highlights(for language: AppLanguage) -> [String] {
        highlightsByLocale?[language.rawValue]
            ?? highlightsByLocale?[AppLanguage.english.rawValue]
            ?? []
    }
}

struct PhraseFinderItem: Decodable {
    let id: String
    let spanish: String
    let englishMeaning: String
    let registerNote: String
    let exampleSentence: String
}

/// Sketched, not authored/used yet — Word Swap topics come after the
/// "goodbye" Phrase Finder walking skeleton proves the mechanic.
struct WordSwapItem: Decodable {
    let id: String
    let overusedWord: String
    let upgrades: [WordSwapUpgrade]
}

struct WordSwapUpgrade: Decodable {
    let spanish: String
    let contextNote: String
}

struct QuizQuestion: Decodable {
    let id: String
    let type: QuestionType
    /// The instruction text ("Complete the phrase.") — the one field on this
    /// type that's genuinely in the learner's interface language, so it's
    /// the only one localized. `options`/`sentenceTemplate`/`acceptedAnswers`
    /// are Spanish learning content and stay Spanish regardless of interface
    /// language, matching the app-wide convention (see Strings_uk.swift's
    /// header comment: interface and explanations translate, Spanish content
    /// doesn't).
    let promptByLocale: [String: String]
    let relatedItemId: String?

    // multipleChoice — Spanish phrases, not localized
    let options: [String]?
    let correctOptionIndex: Int?

    // fillBlank — Spanish sentence/answers, not localized
    let sentenceTemplate: String?
    let acceptedAnswers: [String]?

    func prompt(for language: AppLanguage) -> String {
        promptByLocale[language.rawValue]
            ?? promptByLocale[AppLanguage.english.rawValue]
            ?? promptByLocale.values.first
            ?? ""
    }
}
