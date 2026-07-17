import SwiftUI
import SwiftData

/// Seagull Steven's Vocabulary (spec §12.2): every word Loro is learning or knows,
/// rendered as material tokens. Tap-to-replay is non-counting (U9) — it plays
/// the audio but never calls `onVisitDidComplete`. Includes search + stage
/// filter + sort.
struct LoroVocabularyView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MemoryCard.createdAt, order: .reverse)
    private var cards: [MemoryCard]

    @State private var search = ""
    @State private var filter: StageFilter = .all
    @State private var replayCard: MemoryCard?

    enum StageFilter: String, CaseIterable, Identifiable {
        case all, learning, known
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .learning: return "Learning"
            case .known: return "Known"
            }
        }
    }

    private var filtered: [MemoryCard] {
        cards.filter { card in
            let matchesSearch = search.isEmpty
                || card.content.localizedCaseInsensitiveContains(search)
                || card.translation.localizedCaseInsensitiveContains(search)
            let matchesFilter: Bool = {
                switch filter {
                case .all: return true
                case .learning: return !card.isArchived
                case .known: return card.isArchived
                }
            }()
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 14) {
                Text(L("Seagull Steven's Vocabulary"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.top, 50)

                searchBar
                filterPicker

                if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        LoroImage(asset: .sleeping, size: 150)
                        Text(cards.isEmpty ? L("No words yet") : L("No matches"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColors.textSecondary)
                        if cards.isEmpty {
                            Text(L("Finish a parrot loop in Chat to teach Seagull Steven his first word."))
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(AppColors.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        FlowLayout(hSpacing: 8, vSpacing: 8) {
                            ForEach(filtered) { card in
                                tokenChip(card)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .fullScreenCover(item: $replayCard) { card in
            // U9 non-counting replay: a single-card session that does NOT advance
            // the schedule. Reuses the same player; we pass a one-item queue but
            // dismiss before completion semantics matter — to keep it strictly
            // non-counting we present a dedicated replay player.
            VocabularyReplayView(card: card)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)
            TextField(L("Search words"), text: $search)
                .foregroundColor(AppColors.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(AppColors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.inputBorder, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(StageFilter.allCases) { f in
                Button {
                    filter = f
                } label: {
                    Text(L(f.label))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(filter == f ? .black : AppColors.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(filter == f ? Color.yellow : AppColors.cardBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tokenChip(_ card: MemoryCard) -> some View {
        Button {
            replayCard = card
        } label: {
            HStack(spacing: 8) {
                MaterialTokenView(stage: card.stage, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.content)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    if !card.translation.isEmpty {
                        Text(card.translation)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(card.stage.tokenColor.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(card.stage.tokenColor.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// U9 — non-counting replay. Plays one card's audio once via the shipped
/// `LoopingParrotPlayer` and NEVER touches the schedule.
struct VocabularyReplayView: View {
    let card: MemoryCard
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var player = LoopingParrotPlayer()
    @State private var illustrationService = ParrotService()
    @State private var usingTTS: Bool = false
    @State private var showDeleteConfirmation = false

    private var service: MemoryCardService { MemoryCardService(context: modelContext) }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                HStack {
                    BackButton {
                        player.stop()
                        if usingTTS { TTSService.shared.stop() }
                        dismiss()
                    }
                    Spacer()
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(12)
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal, 12)

                LoroIllustrationView(url: card.illustrationURL, fallback: .listening, size: 160)
                Text(card.content)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                if !card.translation.isEmpty {
                    Text(card.translation)
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
                Text(L("Replay (doesn't change Loro's schedule)"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 24)
        }
        .task {
            if let phrase = resolvePhrase() {
                player.start(phrase: phrase, loops: 1)
            } else {
                usingTTS = true
                TTSService.shared.speak(text: card.content, messageId: card.id, context: "loro")
            }
            await illustrationService.ensureIllustration(for: card)
        }
        .onDisappear {
            player.stop()
            if usingTTS { TTSService.shared.stop() }
        }
        .alert(L("Remove Word?"), isPresented: $showDeleteConfirmation) {
            Button(L("Remove"), role: .destructive) {
                deleteCard()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("\"%@\" will be removed from Seagull Steven's queue and all its learning progress will be lost.", card.content))
        }
    }

    private func deleteCard() {
        player.stop()
        if usingTTS { TTSService.shared.stop() }
        let svc = service
        svc.delete(card)
        Task {
            let remaining = svc.dueCount()
            await MemoryCardNotificationService.shared.refresh(dueCount: remaining)
        }
        dismiss()
    }

    private func resolvePhrase() -> ParrotPhrase? {
        if let sourceId = card.sourceParrotId {
            let descriptor = FetchDescriptor<ParrotPhrase>(predicate: #Predicate { $0.id == sourceId })
            if let found = try? modelContext.fetch(descriptor).first, found.hasAudio { return found }
        }
        guard card.hasAudio else { return nil }
        let transient = ParrotPhrase(messageId: UUID(), sessionId: UUID(), selectedWords: [],
                                     spanishPhrase: card.content, englishTranslation: card.translation)
        transient.segmentPaths = card.audioSegmentPaths
        return transient
    }
}
