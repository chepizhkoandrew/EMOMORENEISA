import Foundation
import SwiftData

enum LessonState: String, Codable {
    case notStarted, inProgress, completed
}

enum LessonPhase: String, Codable {
    case explain, beforePracticeCheckpoint, practice, afterPracticeCheckpoint
}

/// The only new progress state Say It Better introduces: not started / in
/// progress / completed, plus exactly which phase-within-chapter the user is
/// on so resuming mid-lesson picks up where they left off. Deliberately no
/// mastery tiers, no per-item scoring here — that's the point.
@Model
final class LessonProgress {
    @Attribute(.unique) var lessonId: String
    var state: String
    var currentChapterIndex: Int
    var currentPhase: String
    var sessionId: UUID?
    var updatedAt: Date
    /// Which quiz question the current `.practice` attempt is on. Only
    /// meaningful while `currentPhase == .practice`; a fresh attempt resets
    /// it to 0. Needed so an app kill/background mid-quiz doesn't strand the
    /// learner with no "Take a quiz" or "Continue the quiz" button — see
    /// `LessonSessionState.resumePracticeSession()`.
    var practiceQuestionIndex: Int = 0
    /// JSON-encoded `[PracticeAnswerRecord]` for the current `.practice`
    /// attempt (questionId -> wasCorrect). A plain dictionary isn't a
    /// SwiftData-storable attribute type, hence the encoded string.
    var practiceAnswersJSON: String = "[]"

    init(
        lessonId: String,
        state: LessonState = .notStarted,
        currentChapterIndex: Int = 0,
        currentPhase: LessonPhase = .explain,
        sessionId: UUID? = nil,
        updatedAt: Date = Date(),
        practiceQuestionIndex: Int = 0,
        practiceAnswersJSON: String = "[]"
    ) {
        self.lessonId = lessonId
        self.state = state.rawValue
        self.currentChapterIndex = currentChapterIndex
        self.currentPhase = currentPhase.rawValue
        self.sessionId = sessionId
        self.updatedAt = updatedAt
        self.practiceQuestionIndex = practiceQuestionIndex
        self.practiceAnswersJSON = practiceAnswersJSON
    }

    var stateEnum: LessonState { LessonState(rawValue: state) ?? .notStarted }
    var phaseEnum: LessonPhase { LessonPhase(rawValue: currentPhase) ?? .explain }
}
