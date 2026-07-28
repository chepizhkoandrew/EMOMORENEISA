import Foundation
import SwiftData

enum LearnByBookState: String, Codable {
    case notStarted, inProgress, completed
}

/// Mirrors `LessonProgress` — not started / in progress / completed, plus
/// exactly which quiz question the current attempt is on so an app
/// kill/background mid-quiz doesn't strand the learner. No mastery tiers, no
/// per-item historical scoring: a fresh attempt (`Retake quiz`) always wipes
/// `quizAnswersJSON` back to "[]", same as Say It Better's practice attempts.
@Model
final class LearnByBookProgress {
    @Attribute(.unique) var topicId: String
    var state: String
    var quizQuestionIndex: Int = 0
    /// JSON-encoded `[LearnByBookQuizAnswerRecord]` for the current attempt
    /// (questionId -> wasCorrect). A plain dictionary isn't a
    /// SwiftData-storable attribute type, hence the encoded string.
    var quizAnswersJSON: String = "[]"
    var updatedAt: Date

    init(
        topicId: String,
        state: LearnByBookState = .notStarted,
        quizQuestionIndex: Int = 0,
        quizAnswersJSON: String = "[]",
        updatedAt: Date = Date()
    ) {
        self.topicId = topicId
        self.state = state.rawValue
        self.quizQuestionIndex = quizQuestionIndex
        self.quizAnswersJSON = quizAnswersJSON
        self.updatedAt = updatedAt
    }

    var stateEnum: LearnByBookState { LearnByBookState(rawValue: state) ?? .notStarted }
}
