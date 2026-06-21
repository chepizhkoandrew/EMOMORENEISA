import SwiftUI
import SwiftData

/// Progress & Stats (spec §12.3). Pipeline 5-segment bar, forecasted-
/// forgettingness table (soonest-first), and the near-term forecast. All values
/// are computed on demand from card state — nothing is persisted.
struct LoroStatsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var cards: [MemoryCard]

    private var service: MemoryCardService { MemoryCardService(context: modelContext) }

    private var stageCounts: [(stage: MemoryStage, count: Int)] {
        MemoryStage.allCases.map { stage in
            (stage, cards.filter { !$0.isArchived && $0.stage == stage }.count
                + (stage == .microchip ? cards.filter { $0.isArchived }.count : 0))
        }
    }

    private var upcoming: [MemoryCard] {
        cards.filter { !$0.isArchived && !$0.isPaused && $0.nextDueAt != nil }
            .sorted { ($0.nextDueAt ?? .distantFuture) < ($1.nextDueAt ?? .distantFuture) }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Progress")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.top, 50)

                    pipelineCard
                    forecastCard
                    forgettingnessTable
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory pipeline")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)

            GeometryReader { geo in
                let total = max(1, stageCounts.reduce(0) { $0 + $1.count })
                HStack(spacing: 2) {
                    ForEach(stageCounts, id: \.stage) { entry in
                        Rectangle()
                            .fill(entry.stage.tokenColor)
                            .frame(width: geo.size.width * CGFloat(entry.count) / CGFloat(total))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())

            ForEach(stageCounts, id: \.stage) { entry in
                HStack(spacing: 10) {
                    MaterialTokenView(stage: entry.stage, size: 26)
                    Text(entry.stage.displayName)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text("\(entry.count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private var forecastCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("This week")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                Text("\(service.nearTermLoad()) plays")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Known")
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

    @ViewBuilder
    private var forgettingnessTable: some View {
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coming up")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                ForEach(upcoming) { card in
                    HStack(spacing: 10) {
                        MaterialTokenView(stage: card.stage, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.content)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                            if !card.translation.isEmpty {
                                Text(card.translation)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(relativeDue(card.nextDueAt))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
            .padding(16)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.cardBorder, lineWidth: 1))
        }
    }

    private func relativeDue(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
