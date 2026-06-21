import SwiftUI
import SwiftData

/// The Memorize Hub — the 90%-case surface (spec §11.1 / §11.2). Shows El Loro,
/// how many words he knows, the primary "Loro Memorize!" CTA, and the Due-Now
/// list. The CTA opens `SRSPlayerView` for the passive listening session.
struct LoroMemorizeHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<MemoryCard> { !$0.isArchived },
           sort: \MemoryCard.nextDueAt)
    private var activeCards: [MemoryCard]

    @Query(filter: #Predicate<MemoryCard> { $0.isArchived })
    private var knownCards: [MemoryCard]

    @AppStorage("loro.sessionSizeCap") private var sessionSizeCap: Int = 20

    @State private var showSession = false
    @State private var showChat = false
    @State private var now = Date()
    @State private var replayCard: MemoryCard?

    private var service: MemoryCardService { MemoryCardService(context: modelContext) }

    private var dueCards: [MemoryCard] {
        service.buildQueue(sessionCap: sessionSizeCap, now: now)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 22) {
                    header

                    LoroImage(asset: dueCards.isEmpty ? .sleeping : .idle, size: 230)
                        .padding(.top, 4)

                    Text("Seagull Steven knows \(knownCards.count) word\(knownCards.count == 1 ? "" : "s")")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)

                    cta

                    dueSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showSession, onDismiss: { now = Date() }) {
            SRSPlayerView(queue: dueCards)
        }
        .fullScreenCover(isPresented: $showChat) {
            chatDestination
        }
        .fullScreenCover(item: $replayCard) { card in
            VocabularyReplayView(card: card)
        }
        .task {
            now = Date()
            await MemoryCardNotificationService.shared.refresh(dueCount: service.dueCount())
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Home")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(.yellow)
            }
            Spacer()
        }
        .padding(.top, 50)
    }

    @ViewBuilder
    private var chatDestination: some View {
        let authState = AuthState.shared
        if authState.isSignedIn {
            SessionListView()
                .environment(authState)
        } else {
            SignInView()
                .environment(authState)
        }
    }

    @ViewBuilder
    private var cta: some View {
        if !dueCards.isEmpty {
            Button {
                now = Date()
                showSession = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.82, blue: 0.08),
                                    Color(red: 0.88, green: 0.60, blue: 0.02),
                                    Color(red: 0.72, green: 0.42, blue: 0.01)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.30), lineWidth: 1.5)

                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.black.opacity(0.7))
                        Text("Practice Memory")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                        Text("\(dueCards.count)")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Capsule())
                    }
                }
                .frame(height: 64)
                .shadow(color: Color.yellow.opacity(0.45), radius: 18, y: 6)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var dueSection: some View {
        if dueCards.isEmpty {
            Button {
                showChat = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Teach Seagull Steven in Chat")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black.opacity(0.85))
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(Color.yellow)
                .clipShape(Capsule())
            }
            .padding(.top, 12)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Due now")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                ForEach(dueCards) { card in
                    dueRow(card)
                }
            }
            .padding(.top, 8)
        }
    }

    private func dueRow(_ card: MemoryCard) -> some View {
        Button {
            replayCard = card
        } label: {
            HStack(spacing: 12) {
                MaterialTokenView(stage: card.stage, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.content)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(card.stage.horizonLabel)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
                Spacer()
                Text("\(card.exposureCount)/13")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
