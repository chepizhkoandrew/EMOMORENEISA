import SwiftUI

/// Owns the quiz→result transition for one topic within a single
/// `.fullScreenCover` presentation — "Retake quiz" from the result screen
/// just swaps back to a fresh `.quiz` phase in place, no re-presentation.
/// Only the two actions that actually end the presentation ("Review lesson
/// again", "Next topic"/"Back to topics") bubble out to the caller.
struct LearnByBookQuizFlowView: View {
    let topic: LearnByBookTopic
    let hasNextTopic: Bool
    let initialStartIndex: Int
    let initialAnswers: [String: Bool]
    /// Dismiss the cover, staying on the same topic's detail view ("retake
    /// lesson" from the user's request — jump back to vocab/grammar review).
    let onReviewLesson: () -> Void
    /// Dismiss the cover and advance to the next topic (or pop back to the
    /// topic list if this was the last one).
    let onSecondaryAction: () -> Void
    /// Fired once the 3-question attempt is finished, so the host can
    /// persist `.completed` state.
    let onFinish: (LearnByBookQuizResult) -> Void
    /// Fired after every answer/back-navigation mid-attempt, so an app
    /// kill/background mid-quiz can resume instead of losing progress.
    let onProgress: (Int, [String: Bool]) -> Void

    private enum Phase {
        case quiz(LearnByBookQuizSession)
        case result(LearnByBookQuizResult)
    }

    @State private var phase: Phase

    init(
        topic: LearnByBookTopic,
        hasNextTopic: Bool,
        initialStartIndex: Int = 0,
        initialAnswers: [String: Bool] = [:],
        onReviewLesson: @escaping () -> Void,
        onSecondaryAction: @escaping () -> Void,
        onFinish: @escaping (LearnByBookQuizResult) -> Void,
        onProgress: @escaping (Int, [String: Bool]) -> Void
    ) {
        self.topic = topic
        self.hasNextTopic = hasNextTopic
        self.initialStartIndex = initialStartIndex
        self.initialAnswers = initialAnswers
        self.onReviewLesson = onReviewLesson
        self.onSecondaryAction = onSecondaryAction
        self.onFinish = onFinish
        self.onProgress = onProgress
        _phase = State(initialValue: .quiz(LearnByBookQuizSession(
            topic: topic,
            startIndex: initialStartIndex,
            initialAnswers: initialAnswers
        )))
    }

    var body: some View {
        switch phase {
        case .quiz(let session):
            LearnByBookSpokenQuizView(
                session: session,
                onFinish: { result in
                    onFinish(result)
                    withAnimation { phase = .result(result) }
                },
                onCancel: onReviewLesson,
                onProgress: onProgress
            )
        case .result(let result):
            LearnByBookQuizResultView(
                result: result,
                hasNextTopic: hasNextTopic,
                onRetakeQuiz: {
                    phase = .quiz(LearnByBookQuizSession(topic: topic))
                },
                onReviewLesson: onReviewLesson,
                onSecondaryAction: onSecondaryAction
            )
        }
    }
}
