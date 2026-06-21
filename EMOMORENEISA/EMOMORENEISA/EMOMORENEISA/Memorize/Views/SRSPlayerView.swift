import SwiftUI
import SwiftData

/// The passive listening session (spec §12.1). A thin queue / auto-advance
/// coordinator wrapped around the SHIPPED `LoopingParrotPlayer` — it owns ONE
/// player instance and restarts it per card. NO audio playback, segment looping,
/// or `AVAudioPlayer` code lives here (that is `LoopingParrotPlayer`'s job).
/// Background audio, lock-screen Now Playing, and remote commands are inherited
/// for free from the player.
struct SRSPlayerView: View {
    let queue: [MemoryCard]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("loro.autoAdvance") private var autoAdvance: Bool = true

    @State private var player = LoopingParrotPlayer()
    @State private var index: Int = 0
    @State private var finished: Bool = false
    @State private var visitsCompleted: Int = 0
    @State private var archivedThisSession: [MemoryCard] = []
    @State private var celebrationCard: MemoryCard?
    @State private var awaitingNext: Bool = false

    private var service: MemoryCardService { MemoryCardService(context: modelContext) }

    private var currentCard: MemoryCard? {
        guard index < queue.count else { return nil }
        return queue[index]
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                Spacer()
                if finished {
                    summaryView
                } else if let card = currentCard {
                    nowPlaying(card: card)
                } else {
                    summaryView
                }
                Spacer()
                if !finished, currentCard != nil {
                    controls
                    Spacer(minLength: 28)
                }
            }

            if let card = celebrationCard {
                MicrochipCelebrationView(card: card, knownCount: service.knownCount) {
                    celebrationCard = nil
                }
                .transition(.opacity)
            }
        }
        .task { startCurrent() }
        .onChange(of: player.isDone) { _, done in
            guard done else { return }
            handleVisitComplete()
        }
        .onDisappear { player.stop() }
    }

    // MARK: - Playback control

    private func startCurrent() {
        guard let card = currentCard else { finished = true; return }
        guard let phrase = resolvePhrase(for: card) else {
            advance()
            return
        }
        let loops = MemorizeScheduler.repetitionsThisPhase(
            exposureCount: card.exposureCount,
            base: card.repetitionsPerPhaseBase
        )
        player.stop()
        player.start(phrase: phrase, loops: loops)
    }

    private func handleVisitComplete() {
        guard let card = currentCard else { return }
        let wasArchived = card.isArchived
        service.onVisitDidComplete(card)
        visitsCompleted += 1
        if !wasArchived, card.isArchived {
            archivedThisSession.append(card)
            withAnimation { celebrationCard = card }
        }
        // Honor the "Auto-advance words" setting (spec §12.1 / §16.1). When
        // disabled, pause and surface a manual "Next word" affordance instead.
        if autoAdvance {
            advance()
        } else {
            withAnimation { awaitingNext = true }
        }
    }

    private func advance() {
        awaitingNext = false
        index += 1
        if currentCard == nil {
            player.stop()
            withAnimation { finished = true }
        } else {
            startCurrent()
        }
    }

    /// Resolve the real source `ParrotPhrase` for full Now Playing metadata, or
    /// reconstruct a transient one from the card's on-disk WAV paths if the
    /// source was deleted. The WAV bytes are never duplicated.
    private func resolvePhrase(for card: MemoryCard) -> ParrotPhrase? {
        if let sourceId = card.sourceParrotId {
            let descriptor = FetchDescriptor<ParrotPhrase>(
                predicate: #Predicate { $0.id == sourceId }
            )
            if let found = try? modelContext.fetch(descriptor).first, found.hasAudio {
                return found
            }
        }
        guard card.hasAudio else { return nil }
        let transient = ParrotPhrase(
            messageId: UUID(),
            sessionId: UUID(),
            selectedWords: [],
            spanishPhrase: card.content,
            englishTranslation: card.translation
        )
        transient.segmentPaths = card.audioSegmentPaths
        return transient
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Button {
                player.stop()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Done")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(.yellow)
            }
            Spacer()
            if !finished {
                Text("Word \(min(index + 1, queue.count)) of \(queue.count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 8)
    }

    private func nowPlaying(card: MemoryCard) -> some View {
        VStack(spacing: 20) {
            LoroImage(asset: .listening, size: 160)
                .shadow(color: Color.yellow.opacity(0.4), radius: 20)

            VStack(spacing: 8) {
                Text(card.content)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                if !card.translation.isEmpty {
                    Text(card.translation)
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            let loops = MemorizeScheduler.repetitionsThisPhase(
                exposureCount: card.exposureCount,
                base: card.repetitionsPerPhaseBase
            )
            VStack(spacing: 6) {
                Text("Repetition \(min(player.currentLoop + 1, loops)) of \(loops)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                HStack(spacing: 4) {
                    ForEach(0..<max(1, loops), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < player.currentLoop ? Color.yellow : Color.white.opacity(0.2))
                            .frame(height: 6)
                            .animation(.easeInOut(duration: 0.3), value: player.currentLoop)
                    }
                }
                .padding(.horizontal, 32)
            }

            segmentLabel

            HorizonStripView(stage: card.stage)
                .padding(.horizontal, 40)
                .padding(.top, 4)
        }
    }

    private var segmentLabel: some View {
        let labels = [
            "Spanish phrase", "English translation",
            "Spanish × 1", "Spanish × 2", "Spanish × 3",
            "Sentence 1", "Sentence 2"
        ]
        let idx = player.currentSegment
        let label = idx < labels.count ? labels[idx] : ""
        return Text(label)
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(AppColors.textTertiary)
            .animation(.easeInOut, value: player.currentSegment)
    }

    @ViewBuilder
    private var controls: some View {
        if awaitingNext {
            // Auto-advance disabled: the user advances manually (spec §12.1).
            Button {
                advance()
            } label: {
                HStack(spacing: 8) {
                    Text("Next word")
                    Image(systemName: "forward.end.fill")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.yellow.opacity(0.4), radius: 12)
            }
            .padding(.horizontal, 24)
        } else {
            HStack(spacing: 20) {
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 72, height: 72)
                        .background(Color.yellow)
                        .clipShape(Circle())
                        .shadow(color: Color.yellow.opacity(0.4), radius: 12)
                }

                Button {
                    // U1 skip: move to next word without completing this visit
                    // (no exposureCount change). Spec §13 U1.
                    advance()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(AppColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.cardBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var summaryView: some View {
        VStack(spacing: 20) {
            LoroImage(asset: archivedThisSession.isEmpty ? .happy : .excited, size: 200)

            Text(visitsCompleted == 0 ? "Nothing due right now" : "Session complete!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)

            if visitsCompleted > 0 {
                Text("You refreshed \(visitsCompleted) word\(visitsCompleted == 1 ? "" : "s") with Seagull Steven.")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if !archivedThisSession.isEmpty {
                Text("🧠 \(archivedThisSession.count) word\(archivedThisSession.count == 1 ? "" : "s") etched in a microchip — Loro won't forget them for years!")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                dismiss()
            } label: {
                Text("Back to Seagull Steven")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 8)
        }
    }
}
