import SwiftUI
import SwiftData

/// Entry point for "Learn by the Book" (Вчись по підручнику) — a fixed,
/// textbook-style topic curriculum grouped by level, in contrast to Say It
/// Better's flat lesson list or the free-form "Your topic" chat. Styled to
/// match `SayItBetterEntryView`/`SessionListView` (same background, nav
/// title, back button) so the three list-of-list-like screens read as one
/// app.
///
/// Each topic reviews its own vocabulary + grammar focus
/// (`LearnByBookTopicDetailView`), then a 3-question voice-answer quiz
/// (`LearnByBookQuizFlowView`) — rows here show the same per-topic
/// not-started/in-progress/completed status `LessonRowView` shows for Say It
/// Better's lessons.
struct LearnByBookEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let levels = LearnByBookContentBank.shared.levels
    private let topics = LearnByBookContentBank.shared.topics

    @State private var progressByTopicId: [String: LearnByBookProgress] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                topicList
            }
            .navigationTitle(L("Learn by the Book"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
            .navigationDestination(for: LearnByBookTopic.self) { topic in
                LearnByBookTopicDetailView(topic: topic)
            }
        }
        .onAppear { loadProgress() }
    }

    private func loadProgress() {
        let all = (try? modelContext.fetch(FetchDescriptor<LearnByBookProgress>())) ?? []
        progressByTopicId = Dictionary(uniqueKeysWithValues: all.map { ($0.topicId, $0) })
    }

    private var topicList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(levels) { level in
                    let levelTopics = topics.filter { $0.levelId == level.id }
                    if !levelTopics.isEmpty {
                        LearnByBookLevelSection(level: level, topics: levelTopics, progressByTopicId: progressByTopicId)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}

private struct LearnByBookLevelSection: View {
    let level: LearnByBookLevel
    let topics: [LearnByBookTopic]
    let progressByTopicId: [String: LearnByBookProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(level.label(for: LocalizationManager.shared.language))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(LearnByBookLevelStyle.color(for: level.id))
                .clipShape(Capsule())

            VStack(spacing: 10) {
                ForEach(topics) { topic in
                    NavigationLink(value: topic) {
                        LearnByBookTopicRowView(topic: topic, levelId: level.id, progress: progressByTopicId[topic.id])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LearnByBookTopicRowView: View {
    let topic: LearnByBookTopic
    let levelId: String
    let progress: LearnByBookProgress?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LearnByBookLevelStyle.color(for: levelId).opacity(0.85))
                    .frame(width: 46, height: 46)
                Text(levelId.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title(for: LocalizationManager.shared.language))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
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
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch progress?.stateEnum ?? .notStarted {
        case .notStarted:
            Text(LPlural(
                topic.vocabulary.count,
                en: "%d core word", "%d core words",
                uk: "%d базове слово", "%d базові слова", "%d базових слів"
            ))
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

/// Small color tag per level so the topic tree keeps some of the reference
/// curriculum's visual variety (colorful nodes) without introducing a new
/// palette system — reuses `Color.yellow`/`GameColors` neighbors already in
/// the app's vocabulary.
enum LearnByBookLevelStyle {
    static func color(for levelId: String) -> Color {
        switch levelId {
        case "a1": return .yellow
        case "a2": return .orange
        case "b1": return .mint
        case "b2": return .cyan
        case "c1": return Color.purple.opacity(0.7)
        case "c2": return Color.pink.opacity(0.7)
        default:   return .yellow
        }
    }
}
