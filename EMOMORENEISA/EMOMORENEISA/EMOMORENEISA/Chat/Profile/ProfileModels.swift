import Foundation

// MARK: - WordEntry  (SM-2 spaced repetition)

struct WordEntry: Codable, Identifiable {
    var id: UUID
    var word: String
    var translation: String
    var context: String?
    var firstSeen: Date
    var lastReviewed: Date?
    var nextDue: Date
    var intervalDays: Int
    var easeFactor: Double
    var correctStreak: Int
    var totalReviews: Int
    var incorrectCount: Int

    init(word: String, translation: String, context: String? = nil) {
        self.id = UUID()
        self.word = word
        self.translation = translation
        self.context = context
        self.firstSeen = Date()
        self.lastReviewed = nil
        self.nextDue = Date()
        self.intervalDays = 1
        self.easeFactor = 2.5
        self.correctStreak = 0
        self.totalReviews = 0
        self.incorrectCount = 0
    }

    enum CodingKeys: String, CodingKey {
        case id, word, translation, context
        case firstSeen       = "first_seen"
        case lastReviewed    = "last_reviewed"
        case nextDue         = "next_due"
        case intervalDays    = "interval_days"
        case easeFactor      = "ease_factor"
        case correctStreak   = "correct_streak"
        case totalReviews    = "total_reviews"
        case incorrectCount  = "incorrect_count"
    }

    var isDueToday: Bool { nextDue <= Date() }

    mutating func recordCorrect() {
        totalReviews += 1
        correctStreak += 1
        lastReviewed = Date()
        easeFactor = max(1.3, easeFactor + 0.1)
        intervalDays = max(1, Int((Double(intervalDays) * easeFactor).rounded()))
        nextDue = Calendar.current.date(byAdding: .day, value: intervalDays, to: Date()) ?? Date()
    }

    mutating func recordIncorrect() {
        totalReviews += 1
        correctStreak = 0
        incorrectCount += 1
        lastReviewed = Date()
        easeFactor = max(1.3, easeFactor - 0.2)
        intervalDays = 1
        nextDue = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }
}

// MARK: - PhraseEntry

struct PhraseEntry: Codable, Identifiable {
    var id: UUID
    var phrase: String
    var meaning: String
    var firstSeen: Date
    var nextDue: Date
    var intervalDays: Int
    var easeFactor: Double
    var correctStreak: Int
    var totalReviews: Int
    var incorrectCount: Int

    init(phrase: String, meaning: String) {
        self.id = UUID()
        self.phrase = phrase
        self.meaning = meaning
        self.firstSeen = Date()
        self.nextDue = Date()
        self.intervalDays = 1
        self.easeFactor = 2.5
        self.correctStreak = 0
        self.totalReviews = 0
        self.incorrectCount = 0
    }

    enum CodingKeys: String, CodingKey {
        case id, phrase, meaning
        case firstSeen      = "first_seen"
        case nextDue        = "next_due"
        case intervalDays   = "interval_days"
        case easeFactor     = "ease_factor"
        case correctStreak  = "correct_streak"
        case totalReviews   = "total_reviews"
        case incorrectCount = "incorrect_count"
    }

    var isDueToday: Bool { nextDue <= Date() }
}

// MARK: - ErrorEntry

struct ErrorEntry: Codable, Identifiable {
    var id: UUID
    var error: String
    var correction: String
    var rule: String
    var sessionId: UUID?
    var occurredAt: Date
    var recurrenceCount: Int

    init(error: String, correction: String, rule: String, sessionId: UUID? = nil) {
        self.id = UUID()
        self.error = error
        self.correction = correction
        self.rule = rule
        self.sessionId = sessionId
        self.occurredAt = Date()
        self.recurrenceCount = 1
    }

    enum CodingKeys: String, CodingKey {
        case id, error, correction, rule
        case sessionId       = "session_id"
        case occurredAt      = "occurred_at"
        case recurrenceCount = "recurrence_count"
    }
}

// MARK: - SessionSummary

struct SessionSummary: Codable, Identifiable {
    var id: UUID
    var sessionId: UUID
    var date: Date
    var focus: String
    var summary: String
    var wordsIntroduced: Int
    var errorsCorrected: Int

    enum CodingKeys: String, CodingKey {
        case id, date, focus, summary
        case sessionId       = "session_id"
        case wordsIntroduced = "words_introduced"
        case errorsCorrected = "errors_corrected"
    }
}

// MARK: - ExtractionResult (analyst LLM output contract)

struct ExtractionResult: Codable {
    struct WordItem: Codable {
        var word: String
        var translation: String
        var context: String?
    }
    struct PhraseItem: Codable {
        var phrase: String
        var meaning: String
    }
    struct ErrorItem: Codable {
        var error: String
        var correction: String
        var rule: String
    }

    var wordsIntroduced: [WordItem]
    var phrasesIntroduced: [PhraseItem]
    var errorsCorrected: [ErrorItem]
    var topicsCovered: [String]
    var studentLifeFact: String?
    var exerciseTypeDelivered: String?
    var estimatedDifficulty: Int?

    enum CodingKeys: String, CodingKey {
        case wordsIntroduced       = "words_introduced"
        case phrasesIntroduced     = "phrases_introduced"
        case errorsCorrected       = "errors_corrected"
        case topicsCovered         = "topics_covered"
        case studentLifeFact       = "student_life_fact"
        case exerciseTypeDelivered = "exercise_type_delivered"
        case estimatedDifficulty   = "estimated_difficulty"
    }

    static var empty: ExtractionResult {
        ExtractionResult(
            wordsIntroduced: [],
            phrasesIntroduced: [],
            errorsCorrected: [],
            topicsCovered: [],
            studentLifeFact: nil,
            exerciseTypeDelivered: nil,
            estimatedDifficulty: nil
        )
    }
}

// MARK: - Remote analyst event (Supabase insert)

struct RemoteAnalystEvent: Encodable {
    let id: UUID
    let userId: UUID
    let sessionId: UUID
    let messageId: UUID
    let userMessage: String?
    let tutorReply: String
    let extracted: ExtractionResult

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case sessionId   = "session_id"
        case messageId   = "message_id"
        case userMessage = "user_message"
        case tutorReply  = "tutor_reply"
        case extracted
    }
}

// MARK: - Profile v2 partial update (Supabase upsert)

struct ProfileV2Update: Encodable {
    var wordBank: [WordEntry]
    var phraseBank: [PhraseEntry]
    var errorLog: [ErrorEntry]
    var weakAreas: [String]
    var masteredAreas: [String]
    var lifeNotes: String
    var hobbies: [String]
    var exerciseHistory: [String]
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case wordBank        = "word_bank"
        case phraseBank      = "phrase_bank"
        case errorLog        = "error_log"
        case weakAreas       = "weak_areas"
        case masteredAreas   = "mastered_areas"
        case lifeNotes       = "life_notes"
        case hobbies
        case exerciseHistory = "exercise_history"
        case updatedAt       = "updated_at"
    }
}
