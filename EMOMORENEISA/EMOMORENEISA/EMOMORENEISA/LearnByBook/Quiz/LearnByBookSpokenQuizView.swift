import SwiftUI

/// One quiz attempt: the topic's 3 authored questions, in order. Mirrors
/// Say It Better's `PracticeSession` shape exactly.
struct LearnByBookQuizSession: Identifiable {
    let id = UUID()
    let topic: LearnByBookTopic
    /// Which question to open on — 0 for a fresh attempt, or wherever a prior
    /// interrupted attempt (app killed/backgrounded mid-quiz) left off.
    var startIndex: Int = 0
    /// questionId -> wasCorrect carried over from an interrupted attempt, so
    /// the page dots reflect what was already answered on resume.
    var initialAnswers: [String: Bool] = [:]
}

struct LearnByBookQuizAnswer {
    let questionId: String
    let wasCorrect: Bool
}

/// `LearnByBookProgress.quizAnswersJSON`'s element shape — a dictionary isn't
/// directly storable as a SwiftData attribute, so in-progress answers persist
/// as an encoded array of these instead. Mirrors `PracticeAnswerRecord`.
struct LearnByBookQuizAnswerRecord: Codable {
    let questionId: String
    let wasCorrect: Bool
}

struct LearnByBookQuizResult {
    let topicId: String
    let answers: [LearnByBookQuizAnswer]

    var correctCount: Int { answers.filter { $0.wasCorrect }.count }
    var total: Int { answers.count }
}

/// The quiz screen: a back-navigable carousel over the topic's 3 questions,
/// modeled directly on Say It Better's `PracticeCarouselView` (same
/// TabView(selection:) + onFinish/onCancel/onProgress shape) — except every
/// page is `LearnByBookVoiceAnswerQuestionView` (spoken answers only), never
/// the multipleChoice/fillBlank dispatch `PracticeCarouselView` does.
struct LearnByBookSpokenQuizView: View {
    let session: LearnByBookQuizSession
    let onFinish: (LearnByBookQuizResult) -> Void
    /// Called when the user backs out from the first question instead of
    /// answering — a real cancel, distinct from "finished with a result."
    let onCancel: () -> Void
    /// Fired after every answer (and every back-navigation) so the host can
    /// persist exactly where the attempt stands, same resumability Say It
    /// Better's practice carousel has.
    let onProgress: (Int, [String: Bool]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int
    @State private var answers: [String: Bool]

    init(
        session: LearnByBookQuizSession,
        onFinish: @escaping (LearnByBookQuizResult) -> Void,
        onCancel: @escaping () -> Void,
        onProgress: @escaping (Int, [String: Bool]) -> Void
    ) {
        self.session = session
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onProgress = onProgress
        _page = State(initialValue: session.startIndex)
        _answers = State(initialValue: session.initialAnswers)
    }

    private var totalQuestions: Int { session.topic.quiz.count }

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $page) {
                ForEach(Array(session.topic.quiz.enumerated()), id: \.offset) { index, question in
                    LearnByBookVoiceAnswerQuestionView(
                        question: question,
                        questionNumber: index + 1,
                        totalQuestions: totalQuestions,
                        onNext: { correct in handleNext(correct, questionId: question.id, index: index) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            VStack {
                topBar
                Spacer()
                pageIndicator
                    .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea()
    }

    private func handleNext(_ correct: Bool, questionId: String, index: Int) {
        answers[questionId] = correct
        if index < totalQuestions - 1 {
            withAnimation { page = index + 1 }
            onProgress(page, answers)
        } else {
            onProgress(index, answers)
            finish()
        }
    }

    private func finish() {
        let result = LearnByBookQuizResult(
            topicId: session.topic.id,
            answers: session.topic.quiz.map { q in
                LearnByBookQuizAnswer(questionId: q.id, wasCorrect: answers[q.id] ?? false)
            }
        )
        onFinish(result)
    }

    private var topBar: some View {
        HStack {
            BackButton {
                if page > 0 {
                    withAnimation { page -= 1 }
                    onProgress(page, answers)
                } else {
                    onCancel()
                }
            }
            Spacer()
            Text(L("Question %d of %d", page + 1, totalQuestions))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(0..<totalQuestions, id: \.self) { i in
                Capsule()
                    .fill(dotColor(for: i))
                    .frame(width: i == page ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.35), value: page)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        guard index < session.topic.quiz.count else { return AppColors.textTertiary }
        let questionId = session.topic.quiz[index].id
        if index == page { return AppColors.accent }
        if let correct = answers[questionId] {
            return correct ? GameColors.verde : GameColors.rojo
        }
        return AppColors.textTertiary
    }
}
