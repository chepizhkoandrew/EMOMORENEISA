import Foundation
import SwiftData

/// Owns the lesson's runtime state for one `ChatView` instance — the decoded
/// content plus the persisted `LessonProgress` row. Deliberately owned by
/// `ChatView`, not folded into `ChatSession`/`LocalChatSession` itself, so
/// lesson-specific complexity doesn't leak into the shared session model.
@Observable
final class LessonSessionState {
    let lesson: Lesson
    private let progress: LessonProgress
    private let modelContext: ModelContext

    init(lesson: Lesson, progress: LessonProgress, modelContext: ModelContext) {
        self.lesson = lesson
        self.progress = progress
        self.modelContext = modelContext
    }

    var currentPhase: LessonPhase { progress.phaseEnum }
    var currentChapterIndex: Int { progress.currentChapterIndex }
    var isCompleted: Bool { progress.stateEnum == .completed }
    var currentChapter: Chapter? {
        lesson.chapters.indices.contains(currentChapterIndex) ? lesson.chapters[currentChapterIndex] : nil
    }

    /// Most recently completed practice attempt for the current chapter —
    /// nil until the carousel has been finished at least once. Phase 6's
    /// feedback message reads this to reference what actually went right or
    /// wrong, rather than the topic in the abstract.
    private(set) var lastPracticeResult: PracticeResult?

    /// Explain-phase message id → its author-specified highlight substrings.
    /// Deliberately in-memory only, not persisted on `LocalChatMessage`
    /// itself (no new column on the shared, Supabase-synced message model) —
    /// trivially recomputed on resume by zipping the chapter's explanation
    /// chunks against the session's messages in creation order.
    private(set) var highlightsByMessageId: [UUID: [String]] = [:]
    /// Every explain-phase message for the current chapter, in order — the
    /// input "Listen to this chapter again" replays via TTSService.speakQueue.
    private(set) var explanationMessages: [(id: UUID, text: String)] = []

    /// Called both right after inserting a chapter's explanation messages
    /// (fresh session) and once on `ChatView` setup (resumed session) — safe
    /// to call repeatedly, it just rebuilds the map from scratch each time.
    func linkExplanationMessages(_ messages: [LocalChatMessage]) {
        guard let chapter = currentChapter else { return }
        let sorted = messages.sorted { $0.createdAt < $1.createdAt }
        let language = LocalizationManager.shared.language
        explanationMessages = []
        for (chunk, message) in zip(chapter.explanation, sorted) {
            highlightsByMessageId[message.id] = chunk.highlights(for: language)
            explanationMessages.append((id: message.id, text: message.textContent ?? chunk.text(for: language)))
        }
    }

    func highlights(forMessageId messageId: UUID) -> [String] {
        highlightsByMessageId[messageId] ?? []
    }

    /// The message that started the current chapter's explanation — where
    /// "Listen to this chapter again" restarts playback from.
    var firstExplanationMessageId: UUID? { explanationMessages.first?.id }

    /// Called once chapter's explanation beat has finished autoplaying.
    func markExplainDone() {
        setPhase(.beforePracticeCheckpoint)
    }

    /// Builds the carousel's input from the current chapter's authored
    /// questions for a brand-new attempt ("Start practice" / "Retake the
    /// quiz" / "Restart the quiz") — always from question 0, discarding
    /// whatever a prior interrupted attempt had left in progress. `ChatView`
    /// assigns the result to its own `practiceSession` state to drive the
    /// `.fullScreenCover`.
    func buildPracticeSession() -> PracticeSession? {
        guard let chapter = currentChapter else { return nil }
        progress.practiceQuestionIndex = 0
        progress.practiceAnswersJSON = "[]"
        setPhase(.practice)
        return PracticeSession(chapterId: chapter.id, questions: chapter.quiz)
    }

    /// Rebuilds the carousel's input picking up exactly where an interrupted
    /// attempt left off — the fix for the dead-end where backgrounding or
    /// force-quitting mid-quiz left `currentPhase` stuck at `.practice` with
    /// no persisted position, so reopening the lesson showed no dock at all.
    func resumePracticeSession() -> PracticeSession? {
        guard let chapter = currentChapter else { return nil }
        let startIndex = min(progress.practiceQuestionIndex, max(chapter.quiz.count - 1, 0))
        return PracticeSession(
            chapterId: chapter.id,
            questions: chapter.quiz,
            startIndex: startIndex,
            initialAnswers: practiceAnswers
        )
    }

    /// questionId -> wasCorrect for the in-progress `.practice` attempt,
    /// decoded from `progress.practiceAnswersJSON`.
    private var practiceAnswers: [String: Bool] {
        guard let data = progress.practiceAnswersJSON.data(using: .utf8),
              let records = try? JSONDecoder().decode([PracticeAnswerRecord].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.questionId, $0.wasCorrect) })
    }

    /// Called after every answer (and every back-navigation) inside an active
    /// `.practice` attempt so a kill/background mid-quiz never loses more
    /// than the single question in flight.
    func recordPracticeProgress(index: Int, answers: [String: Bool]) {
        progress.practiceQuestionIndex = index
        let records = answers.map { PracticeAnswerRecord(questionId: $0.key, wasCorrect: $0.value) }
        if let data = try? JSONEncoder().encode(records), let json = String(data: data, encoding: .utf8) {
            progress.practiceAnswersJSON = json
        }
        save()
    }

    /// Called when the practice carousel dismisses with a result (whether
    /// from "Start practice" or "Retake the quiz").
    func recordPracticeResult(_ result: PracticeResult) {
        lastPracticeResult = result
        setPhase(.afterPracticeCheckpoint)
    }

    /// Called when the user backs out of the practice screen from its first
    /// question instead of answering — phase was left stuck at `.practice`
    /// forever otherwise (nothing else in the state machine ever moves it
    /// off `.practice` except `recordPracticeResult`), which silently wiped
    /// the Next Steps dock and made the lesson unrecoverable without
    /// reinstalling the app. Reverts to wherever the dock was before this
    /// attempt started — a prior completed result means this was a retake,
    /// so it goes back to the after-practice checkpoint, not all the way to
    /// square one.
    func cancelPractice() {
        setPhase(lastPracticeResult != nil ? .afterPracticeCheckpoint : .beforePracticeCheckpoint)
    }

    /// The one message that's Madrid's auto-triggered post-practice feedback
    /// (as opposed to a genuine follow-up answer) — set by `ChatView` right
    /// after inserting it, so `MessageBubbleView` knows to render the
    /// per-question result chips and the distinct background on exactly
    /// that message, never on an ordinary explanation or Q&A bubble.
    private(set) var feedbackMessageId: UUID?

    func markFeedbackMessage(_ id: UUID) {
        feedbackMessageId = id
    }

    func practiceSummary(forMessageId id: UUID) -> PracticeResult? {
        id == feedbackMessageId ? lastPracticeResult : nil
    }

    /// True once fewer than half the questions were answered correctly —
    /// the signal to swap which Next-steps button reads as the recommended
    /// one ("Retake the quiz" over "Next chapter").
    var practiceWasWeak: Bool {
        guard let result = lastPracticeResult, !result.answers.isEmpty else { return false }
        let correct = result.answers.filter(\.wasCorrect).count
        return correct * 2 < result.answers.count
    }

    /// Advances past the current chapter without practicing — the deliberate
    /// escape hatch for someone previewing or not ready to speak right now.
    /// Also what "Next chapter" does after practice, since both are "move
    /// past this chapter" in the end.
    func skipToNextChapter() {
        advanceToNextChapterOrComplete()
    }

    func advanceToNextChapterOrComplete() {
        let nextIndex = progress.currentChapterIndex + 1
        if lesson.chapters.indices.contains(nextIndex) {
            progress.currentChapterIndex = nextIndex
            setPhase(.explain)
        } else {
            setPhase(.afterPracticeCheckpoint)
            progress.state = LessonState.completed.rawValue
            save()
        }
    }

    private func setPhase(_ phase: LessonPhase) {
        progress.currentPhase = phase.rawValue
        if progress.stateEnum == .notStarted {
            progress.state = LessonState.inProgress.rawValue
        }
        save()
    }

    private func save() {
        progress.updatedAt = Date()
        try? modelContext.save()
    }
}
