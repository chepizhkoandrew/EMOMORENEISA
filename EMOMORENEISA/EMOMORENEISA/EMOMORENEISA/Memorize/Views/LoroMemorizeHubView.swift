import SwiftUI
import SwiftData
import Combine
import AVFoundation

/// The Memorize Hub — the 90%-case surface (spec §11.1 / §11.2). Shows El Loro,
/// how many words he knows, the primary "Loro Memorize!" CTA, and the Due-Now
/// list. The CTA opens `SRSPlayerView` for the passive listening session.
struct LoroMemorizeHubView: View {
    var showsBackButton: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<MemoryCard> { !$0.isArchived },
           sort: \MemoryCard.nextDueAt)
    private var activeCards: [MemoryCard]

    @AppStorage("loro.sessionSizeCap") private var sessionSizeCap: Int = 20

    @State private var showSession = false
    @State private var showChat = false
    @State private var now = Date()
    @State private var replayCard: MemoryCard?

    // Same pattern as the professor-dog's bubble on the home screen: one
    // phrase at a time, typed in, spoken, held, then deleted.
    private let loroPhrases: [(es: String, meaning: String)] = [
        ("La vida es loca", "Life is crazy"),
        ("Tenemos que trabajar", "We have to work"),
        ("Ah, si-si o no?", "Ah, yes-yes or no?"),
        ("Huele a pollo?", "Smells like chicken?")
    ]
    @State private var loroDisplayedText = ""
    @State private var loroPhraseIndex = 0
    @State private var loroCharIndex = 0
    @State private var loroCursorVisible = true
    @State private var loroTypeTask: Task<Void, Never>? = nil
    @State private var loroBubblePlayer: AVAudioPlayer? = nil

    private var service: MemoryCardService { MemoryCardService(context: modelContext) }

    private var dueCards: [MemoryCard] {
        service.buildQueue(sessionCap: sessionSizeCap, now: now)
    }

    private var dueLaterCards: [MemoryCard] {
        let dueIds = Set(dueCards.map { $0.id })
        return activeCards.filter { card in
            !dueIds.contains(card.id)
                && !card.isPaused
                && card.nextDueAt != nil
                && card.nextDueAt! > now
        }
        .sorted { ($0.nextDueAt ?? .distantFuture) < ($1.nextDueAt ?? .distantFuture) }
    }

    var body: some View {
        GeometryReader { geo in
            // Match the home professor-dog's hero: same `HomeLayout.dogHeight`
            // target and the same `* 0.50` bubble lift + 86pt bubble. The dog art
            // is a tall portrait (renders ~150pt wide at full height); the seagull
            // art is square, so we clamp its side by the row width — otherwise a
            // full-height square would fill the row and crush the bubble. This
            // makes the seagull read as big as the dog while both bubbles keep a
            // fair share of the width.
            let heroSide = min(HomeLayout.dogHeight(geo.size.height), (geo.size.width - 40) * 0.55)
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        HStack(alignment: .bottom, spacing: 12) {
                            LoroImage(asset: dueCards.isEmpty ? .sleeping : .idle, size: heroSide)

                            loroSpeechBubbleView
                                .padding(.bottom, heroSide * 0.50)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(height: heroSide)
                        .padding(.top, 4)

                        cta

                        dueSection

                        dueLaterSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
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
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            now = Date()
        }
        .onAppear { startLoroTypewriter() }
        .onDisappear { stopLoroAmbient() }
        // `fullScreenCover` never fires `.onDisappear` on the view it covers
        // — this screen stays mounted underneath, so relying on `onDisappear`
        // alone left the seagull's narration running (and audible) right
        // through the queue playback it just launched. Each presentation
        // needs its own explicit stop, mirroring the home screen's dog.
        .onChange(of: showSession) { _, isShowing in
            if isShowing { stopLoroAmbient() } else { startLoroTypewriter() }
        }
        .onChange(of: showChat) { _, isShowing in
            if isShowing { stopLoroAmbient() } else { startLoroTypewriter() }
        }
        .onChange(of: replayCard) { _, card in
            if card != nil { stopLoroAmbient() } else { startLoroTypewriter() }
        }
    }

    private func stopLoroAmbient() {
        loroTypeTask?.cancel()
        loroBubblePlayer?.stop()
        loroBubblePlayer = nil
    }

    private var header: some View {
        HStack {
            if showsBackButton {
                BackButton { dismiss() }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
        }
        .padding(.top, 50)
    }

    // MARK: - Speech Bubble (same pattern as the professor-dog's bubble)

    private var loroSpeechBubbleView: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.yellow)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            SpeechTailShape()
                .fill(Color.yellow)
                .frame(width: 11, height: 9)
                .offset(x: -10, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(loroDisplayedText + (loroCursorVisible ? "|" : " "))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)

                Text(L(loroPhrases[loroPhraseIndex].meaning))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86)
    }

    private func playLoroBubbleSound(index: Int) {
        // Falls back to the Spanish-only clip if the localized file is
        // missing, and no-ops entirely if neither exists yet.
        let langSuffix: String
        switch LocalizationManager.shared.language {
        case .ukrainian: langSuffix = "uk"
        case .english:   langSuffix = "en"
        }
        let localizedName = "loro_bubble_\(index)_\(langSuffix)"
        let url = Bundle.main.url(forResource: localizedName, withExtension: "mp3")
            ?? Bundle.main.url(forResource: "loro_bubble_\(index)", withExtension: "mp3")
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            loroBubblePlayer = try AVAudioPlayer(contentsOf: url)
            loroBubblePlayer?.volume = 0.7
            loroBubblePlayer?.play()
        } catch {}
    }

    private func startLoroTypewriter() {
        loroTypeTask?.cancel()
        loroDisplayedText = ""
        loroPhraseIndex = 0
        loroCharIndex = 0

        loroTypeTask = Task {
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run { loroCursorVisible.toggle() }
                }
            }

            while !Task.isCancelled {
                let phrase = loroPhrases[loroPhraseIndex].es

                let duration = await MainActor.run { () -> TimeInterval in
                    playLoroBubbleSound(index: loroPhraseIndex)
                    return loroBubblePlayer?.duration ?? 0
                }

                await MainActor.run { loroCharIndex = 0; loroDisplayedText = "" }
                while loroCharIndex < phrase.count && !Task.isCancelled {
                    await MainActor.run {
                        loroCharIndex += 1
                        loroDisplayedText = String(phrase.prefix(loroCharIndex))
                    }
                    try? await Task.sleep(nanoseconds: 70_000_000)
                }

                let start = Date()
                let minHold: TimeInterval = 2.2
                let cap = max(duration, minHold) + 0.5
                while !Task.isCancelled {
                    let playing = await MainActor.run { loroBubblePlayer?.isPlaying ?? false }
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed >= cap { break }
                    if !playing && elapsed >= minHold { break }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }

                while loroCharIndex > 0 && !Task.isCancelled {
                    await MainActor.run {
                        loroCharIndex -= 1
                        loroDisplayedText = String(phrase.prefix(loroCharIndex))
                    }
                    try? await Task.sleep(nanoseconds: 32_000_000)
                }

                await MainActor.run { loroPhraseIndex = (loroPhraseIndex + 1) % loroPhrases.count }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
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

    private var nextDueInText: String? {
        let upcoming = activeCards
            .filter { !dueCards.contains($0) && !$0.isPaused && ($0.nextDueAt ?? .distantPast) > now }
            .sorted { ($0.nextDueAt ?? .distantFuture) < ($1.nextDueAt ?? .distantFuture) }
        guard let nextDate = upcoming.first?.nextDueAt else { return nil }
        let diff = max(0, nextDate.timeIntervalSince(now))
        if diff < 3600 {
            let mins = Int(diff / 60) + 1
            return L("%d min", mins)
        }
        let hours = Int(diff / 3600)
        if hours < 24 { return L("%d hour", hours) }
        let days = Int(diff / 86400) + 1
        return L("%d day", days)
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
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.7))
                        Text(L("Practice Memory"))
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                    }
                }
                .frame(height: 64)
                .shadow(color: Color.yellow.opacity(0.45), radius: 18, y: 6)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 30, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                if let timeStr = nextDueInText {
                    Text(L("Next practice in %@", timeStr))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                } else if activeCards.isEmpty {
                    Text(L("No words yet"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                    Text(L("Use Explore mode to discover and add words to your queue"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(L("Teach Seagull Steven in Chat"))
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
                Text(L("Due now"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                ForEach(dueCards) { card in
                    dueRow(card, subtitle: nil)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var dueLaterSection: some View {
        if !dueLaterCards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Due later"))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                ForEach(dueLaterCards) { card in
                    dueRow(card, subtitle: timeUntilDueLabel(card))
                }
            }
            .padding(.top, 8)
        }
    }

    private func timeUntilDueLabel(_ card: MemoryCard) -> String? {
        guard let due = card.nextDueAt else { return nil }
        let diff = due.timeIntervalSince(now)
        guard diff > 0 else { return nil }
        if diff < 3600 {
            let mins = max(1, Int(diff / 60))
            return L("in %d min", mins)
        }
        let hours = Int(diff / 3600)
        if hours < 24 {
            return L("in %d hour", hours)
        }
        let days = Int(diff / 86400) + 1
        return L("in %d day", days)
    }

    private func dueRow(_ card: MemoryCard, subtitle: String?) -> some View {
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
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                Spacer()
                Text("\(card.exposureCount)/13")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, design: .rounded))
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
