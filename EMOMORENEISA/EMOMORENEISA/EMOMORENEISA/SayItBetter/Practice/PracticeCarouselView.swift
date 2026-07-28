import SwiftUI

/// One practice run: exactly the chapter's 5 authored questions, in order.
struct PracticeSession: Identifiable {
    let id = UUID()
    let chapterId: String
    let questions: [QuizQuestion]
    /// Which question to open on — 0 for a fresh attempt, or wherever a prior
    /// interrupted attempt (app killed/backgrounded mid-quiz) left off.
    var startIndex: Int = 0
    /// questionId -> wasCorrect carried over from an interrupted attempt, so
    /// the page dots reflect what was already answered on resume.
    var initialAnswers: [String: Bool] = [:]
}

struct PracticeAnswer {
    let questionId: String
    let wasCorrect: Bool
}

/// `LessonProgress.practiceAnswersJSON`'s element shape — a dictionary isn't
/// directly storable as a SwiftData attribute, so in-progress answers persist
/// as an encoded array of these instead.
struct PracticeAnswerRecord: Codable {
    let questionId: String
    let wasCorrect: Bool
}

struct PracticeResult {
    let chapterId: String
    let answers: [PracticeAnswer]
}

/// The practice screen: a back-navigable carousel over the chapter's 5
/// questions, modeled directly on `OnboardingCarouselView`'s
/// TabView(selection:) + explicit onBack/onNext-per-page pattern — the only
/// existing back-navigable multi-item flow in the app (Parrot and
/// `SRSPlayerView` are both forward-only or single-item).
struct PracticeCarouselView: View {
    let session: PracticeSession
    let onFinish: (PracticeResult) -> Void
    /// Called when the user backs out from the first question instead of
    /// answering — a real cancel, distinct from "finished with a result."
    /// Must always be called instead of a bare `dismiss()`: leaving the
    /// lesson's phase machine in `.practice` with nothing to move it back
    /// out is what caused the "stuck, dock gone forever" bug.
    let onCancel: () -> Void
    /// Fired after every answer (and every back-navigation) so the host can
    /// persist exactly where the attempt stands — the fix for the sibling
    /// bug where an app kill/background mid-quiz left no way to resume: the
    /// dock just vanished with no "Take a quiz" or "Continue the quiz"
    /// button at all.
    let onProgress: (Int, [String: Bool]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int
    /// questionId -> wasCorrect. Answers stay editable when navigating back —
    /// re-answering a question just overwrites its entry here.
    @State private var answers: [String: Bool]

    init(
        session: PracticeSession,
        onFinish: @escaping (PracticeResult) -> Void,
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

    private var totalQuestions: Int { session.questions.count }

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $page) {
                ForEach(Array(session.questions.enumerated()), id: \.offset) { index, question in
                    questionPage(question, index: index)
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

    @ViewBuilder
    private func questionPage(_ question: QuizQuestion, index: Int) -> some View {
        let onNext: (Bool) -> Void = { wasCorrect in
            answers[question.id] = wasCorrect
            if index < totalQuestions - 1 {
                withAnimation { page = index + 1 }
                onProgress(page, answers)
            } else {
                onProgress(index, answers)
                finish()
            }
        }

        switch question.type {
        case .multipleChoice:
            QuizQuestionView(
                question: question,
                questionNumber: index + 1,
                totalQuestions: totalQuestions,
                initialSelectedIndex: nil,
                onNext: onNext
            )
        case .fillBlank:
            FillBlankQuestionView(
                question: question,
                questionNumber: index + 1,
                totalQuestions: totalQuestions,
                onNext: onNext
            )
        case .sayItAloud:
            // Reserved for a future STT question type — not built yet, and
            // v1 content never includes one, so this is unreachable in
            // practice. Skip forward rather than get stuck on it.
            Color.clear.onAppear { onNext(false) }
        }
    }

    private func finish() {
        let result = PracticeResult(
            chapterId: session.chapterId,
            answers: session.questions.map { q in
                PracticeAnswer(questionId: q.id, wasCorrect: answers[q.id] ?? false)
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
                    dismiss()
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
        guard index < session.questions.count else { return AppColors.textTertiary }
        let questionId = session.questions[index].id
        if index == page { return AppColors.accent }
        if let correct = answers[questionId] {
            return correct ? GameColors.verde : GameColors.rojo
        }
        return AppColors.textTertiary
    }
}
