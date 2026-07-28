import SwiftUI
import SwiftData

/// The Grammar Block entry point for Say It Better — a lesson list so users
/// can jump back into (or resume) any lesson without scrolling through a
/// long card list. Styled identically to `SessionListView` ("My Chats") —
/// same background, nav title, back button, and row card — since both are
/// just list-of-list-like-things screens and shouldn't look like two
/// different apps.
struct SayItBetterEntryView: View {
    let onSessionCreated: (LocalChatSession) -> Void

    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var lessons: [Lesson] = []
    @State private var progressByLessonId: [String: LessonProgress] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                lessonList
            }
            .navigationTitle(L("Say It Better"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
        }
        .onAppear { loadLessons() }
    }

    private var lessonList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(lessons, id: \.id) { lesson in
                    Button {
                        Task { await openLesson(lesson) }
                    } label: {
                        LessonRowView(lesson: lesson, progress: progressByLessonId[lesson.id])
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func loadLessons() {
        lessons = SayItBetterContentBank.shared.lessons.values.sorted { $0.order < $1.order }
        for lesson in lessons {
            progressByLessonId[lesson.id] = existingProgress(for: lesson.id)
        }
    }

    private func openLesson(_ lesson: Lesson) async {
        guard let userId = authState.userId else { return }

        if let progress = progressByLessonId[lesson.id],
           let sessionId = progress.sessionId,
           let session = existingSession(id: sessionId) {
            onSessionCreated(session)
            return
        }

        let session = LocalChatSession(
            userId: userId,
            mode: .lesson,
            title: lesson.title(for: LocalizationManager.shared.language),
            topic: lesson.id,
            lessonId: lesson.id
        )
        modelContext.insert(session)

        let progress = LessonProgress(lessonId: lesson.id, sessionId: session.id)
        modelContext.insert(progress)

        try? modelContext.save()
        Task {
            await SupabaseSyncService.shared.upsertSession(session, userId: userId)
        }
        AnalyticsService.shared.track(.sessionCreated(mode: SessionMode.lesson.rawValue))

        onSessionCreated(session)
    }

    private func existingProgress(for lessonId: String) -> LessonProgress? {
        let descriptor = FetchDescriptor<LessonProgress>(
            predicate: #Predicate { $0.lessonId == lessonId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func existingSession(id: UUID) -> LocalChatSession? {
        let descriptor = FetchDescriptor<LocalChatSession>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

/// Mirrors `SessionRowView` (Chat Tutor's list row) exactly — icon tile,
/// title, status line, chevron — so the two list screens read as one
/// consistent pattern instead of two.
struct LessonRowView: View {
    let lesson: Lesson
    let progress: LessonProgress?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.pink.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(SessionMode.lesson.homeMenuAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title(for: LocalizationManager.shared.language))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                statusLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch progress?.stateEnum ?? .notStarted {
        case .notStarted:
            Text(L("Not started"))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        case .inProgress:
            Text(L("In progress"))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(.yellow.opacity(0.8))
        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(L("Completed"))
            }
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundColor(GameColors.verde)
        }
    }
}
