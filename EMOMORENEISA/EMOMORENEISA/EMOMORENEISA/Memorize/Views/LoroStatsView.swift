import SwiftUI
import SwiftData

struct LoroStatsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MemoryCard.createdAt, order: .reverse)
    private var cards: [MemoryCard]

    @State private var stageFilter: StageFilter = .all
    @State private var search = ""
    @State private var replayCard: MemoryCard?

    enum StageFilter: Equatable {
        case all
        case stage(MemoryStage)
        case known

        var label: String {
            switch self {
            case .all: return L("All")
            case .stage(let s): return L(s.displayName)
            case .known: return L("Known")
            }
        }

        static var allCases: [StageFilter] {
            [.all] + MemoryStage.allCases.map { .stage($0) } + [.known]
        }
    }

    private var service: MemoryCardService { MemoryCardService(context: modelContext) }

    private var stageCounts: [(stage: MemoryStage, count: Int)] {
        MemoryStage.allCases.map { stage in
            (stage, cards.filter { !$0.isArchived && $0.stage == stage }.count
                + (stage == .microchip ? cards.filter { $0.isArchived }.count : 0))
        }
    }

    private var filteredCards: [MemoryCard] {
        cards.filter { card in
            let matchesSearch = search.isEmpty
                || card.content.localizedCaseInsensitiveContains(search)
                || card.translation.localizedCaseInsensitiveContains(search)
            let matchesFilter: Bool = {
                switch stageFilter {
                case .all: return true
                case .stage(let s): return !card.isArchived && card.stage == s
                case .known: return card.isArchived
                }
            }()
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L("Progress"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.top, 96)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    pipelineCard
                    statsRow
                    filterSection
                    wordList
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(item: $replayCard) { card in
            VocabularyReplayView(card: card)
        }
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Memory pipeline"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)

            GeometryReader { geo in
                let total = max(1, stageCounts.reduce(0) { $0 + $1.count })
                HStack(spacing: 2) {
                    ForEach(stageCounts, id: \.stage) { entry in
                        Button {
                            stageFilter = .stage(entry.stage)
                        } label: {
                            Rectangle()
                                .fill(entry.stage.tokenColor)
                                .frame(width: geo.size.width * CGFloat(entry.count) / CGFloat(total))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())

            ForEach(stageCounts, id: \.stage) { entry in
                Button {
                    stageFilter = .stage(entry.stage)
                } label: {
                    HStack(spacing: 10) {
                        MaterialTokenView(stage: entry.stage, size: 26)
                        Text(L(entry.stage.displayName))
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(
                                stageFilter == .stage(entry.stage) ? entry.stage.tokenColor : AppColors.textSecondary
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private var statsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("This week"))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                Text(L("%d plays", service.nearTermLoad()))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(L("Known"))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                Text("\(service.knownCount)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
            }
        }
        .padding(16)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StageFilter.allCases, id: \.label) { f in
                        Button {
                            stageFilter = f
                        } label: {
                            Text(f.label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(stageFilter == f ? .black : AppColors.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(stageFilter == f ? Color.yellow : AppColors.cardBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var wordList: some View {
        if filteredCards.isEmpty {
            VStack(spacing: 10) {
                LoroImage(asset: .sleeping, size: 120)
                Text(cards.isEmpty ? L("No words yet") : L("No matches"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        } else {
            FlowLayout(hSpacing: 8, vSpacing: 8) {
                ForEach(filteredCards) { card in
                    tokenChip(card)
                }
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
