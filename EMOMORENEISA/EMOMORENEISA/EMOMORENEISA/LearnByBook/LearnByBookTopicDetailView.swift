import SwiftUI
import SwiftData

/// A single curriculum topic: vocabulary + grammar review, then a 3-question
/// voice-answer quiz (see `LearnByBookQuizFlowView`). `currentTopic` is
/// mutable rather than a fixed `let` so "Next topic" can swap this same view
/// instance to the next node in the curriculum instead of pushing a new
/// screen — mirrors `ModeSelectorView`'s "swap content, not the whole view"
/// convention.
struct LearnByBookTopicDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var currentTopic: LearnByBookTopic
    @State private var progress: LearnByBookProgress?
    @State private var activeQuiz: ActiveQuizContext?

    init(topic: LearnByBookTopic) {
        _currentTopic = State(initialValue: topic)
    }

    private struct ActiveQuizContext: Identifiable {
        let id = UUID()
        let startIndex: Int
        let answers: [String: Bool]
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        vocabularySection
                        grammarSection
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                }
                quizCTA
            }
        }
        .navigationTitle(currentTopic.title(for: LocalizationManager.shared.language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { loadProgress() }
        .onChange(of: currentTopic.id) { _, _ in loadProgress() }
        .fullScreenCover(item: $activeQuiz) { ctx in
            LearnByBookQuizFlowView(
                topic: currentTopic,
                hasNextTopic: nextTopic != nil,
                initialStartIndex: ctx.startIndex,
                initialAnswers: ctx.answers,
                onReviewLesson: { activeQuiz = nil },
                onSecondaryAction: {
                    activeQuiz = nil
                    if let next = nextTopic {
                        currentTopic = next
                    } else {
                        dismiss()
                    }
                },
                onFinish: { result in persistCompletion(result) },
                onProgress: { index, answers in persistProgress(index: index, answers: answers) }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(currentTopic.levelId.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(LearnByBookLevelStyle.color(for: currentTopic.levelId))
                .clipShape(Capsule())
            statusPill
            Spacer()
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch progress?.stateEnum ?? .notStarted {
        case .notStarted:
            EmptyView()
        case .inProgress:
            Text(L("In progress"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.yellow.opacity(0.9))
        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(L("Completed"))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(GameColors.verde)
        }
    }

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Core words & phrases"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                ForEach(currentTopic.vocabulary) { item in
                    LearnByBookVocabularyRow(item: item)
                }
            }
        }
    }

    private var grammarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Grammar focus"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                ForEach(currentTopic.grammarFocus) { focus in
                    LearnByBookGrammarRow(focus: focus)
                }
            }
        }
    }

    // MARK: - Quiz CTA

    private var quizCTA: some View {
        Button {
            startQuiz()
        } label: {
            Text(ctaLabel)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColors.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    private var ctaLabel: String {
        switch progress?.stateEnum ?? .notStarted {
        case .notStarted: return L("Start quiz")
        case .inProgress: return L("Resume quiz")
        case .completed: return L("Retake quiz")
        }
    }

    // MARK: - Progress persistence

    private var nextTopic: LearnByBookTopic? {
        let all = LearnByBookContentBank.shared.topics
        guard let index = all.firstIndex(where: { $0.id == currentTopic.id }), index + 1 < all.count else {
            return nil
        }
        return all[index + 1]
    }

    private func loadProgress() {
        progress = existingProgress(for: currentTopic.id)
    }

    private func existingProgress(for topicId: String) -> LearnByBookProgress? {
        let descriptor = FetchDescriptor<LearnByBookProgress>(
            predicate: #Predicate { $0.topicId == topicId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func startQuiz() {
        let existing = progress ?? {
            let created = LearnByBookProgress(topicId: currentTopic.id)
            modelContext.insert(created)
            progress = created
            return created
        }()

        var answers: [String: Bool] = [:]
        if let records = try? JSONDecoder().decode([LearnByBookQuizAnswerRecord].self, from: Data(existing.quizAnswersJSON.utf8)) {
            for r in records { answers[r.questionId] = r.wasCorrect }
        }
        let startIndex = existing.stateEnum == .inProgress ? existing.quizQuestionIndex : 0

        if existing.stateEnum == .notStarted {
            existing.state = LearnByBookState.inProgress.rawValue
            existing.updatedAt = Date()
        }
        try? modelContext.save()

        activeQuiz = ActiveQuizContext(
            startIndex: existing.stateEnum == .completed ? 0 : startIndex,
            answers: existing.stateEnum == .completed ? [:] : answers
        )
    }

    private func persistProgress(index: Int, answers: [String: Bool]) {
        guard let progress else { return }
        progress.quizQuestionIndex = index
        let records = answers.map { LearnByBookQuizAnswerRecord(questionId: $0.key, wasCorrect: $0.value) }
        progress.quizAnswersJSON = (try? String(data: JSONEncoder().encode(records), encoding: .utf8)) ?? "[]"
        progress.updatedAt = Date()
        try? modelContext.save()
    }

    private func persistCompletion(_ result: LearnByBookQuizResult) {
        guard let progress else { return }
        progress.state = LearnByBookState.completed.rawValue
        progress.quizQuestionIndex = 0
        progress.quizAnswersJSON = "[]"
        progress.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct LearnByBookVocabularyRow: View {
    let item: LearnByBookVocabularyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.spanish)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
                Text("— \(item.englishMeaning)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
            }
            Text(item.registerNote)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
            Text(item.exampleSentence)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .italic()
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct LearnByBookGrammarRow: View {
    let focus: LearnByBookGrammarFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(focus.title(for: LocalizationManager.shared.language))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
            Text(focus.explanation(for: LocalizationManager.shared.language))
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.purple.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
