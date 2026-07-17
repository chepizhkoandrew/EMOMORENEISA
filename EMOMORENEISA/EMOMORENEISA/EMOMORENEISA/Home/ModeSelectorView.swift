import SwiftUI
import SwiftData
import AVFoundation

struct ModeSelectorView: View {
    let onVerbGame: () -> Void

    /// Which set of cards is currently showing. Switching levels never tears
    /// this view down — only the card content transitions — so the dog,
    /// its speech bubble, the background, and the music never restart.
    private enum HomeLevel { case top, speaking, memory, grammar }
    @State private var level: HomeLevel = .top
    private let cardTransition = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// A genuinely separate screen reached from a card (as opposed to a
    /// `level` switch, which stays on this same screen).
    private enum LeafDestination: Identifiable {
        case topicFlow, streetViewFlow, rolePlay, memoryCalendar, musicPlaceholder, explainRules, freeForum
        var id: Self { self }
    }
    @State private var activeLeaf: LeafDestination? = nil

    /// True from the moment a new chat session is created until it's actually
    /// launched (there's a deliberate 0.35s delay between the two). Without
    /// this, `activeLeaf` clearing to nil fires the "resume typewriter +
    /// music" branch immediately, only for `launchedSession` to kill it again
    /// 0.35s later — a real restart-then-stop race on every single session
    /// launch, not just a theoretical one.
    @State private var pendingSessionLaunch = false
    @State private var launchedSession: LocalChatSession? = nil
    @State private var appear = false
    @State private var speakingCardPressed = false
    @State private var memoryCardPressed = false
    @State private var grammarCardPressed = false
    @State private var rolePlayCardPressed = false
    @State private var yourTopicCardPressed = false
    @State private var calendarCardPressed = false
    @State private var musicCardPressed = false
    @State private var explainRulesCardPressed = false
    @State private var verbsTimesCardPressed = false
    @State private var freeForumCardPressed = false
    @State private var bubblePlayer: AVAudioPlayer? = nil
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext

    private let phrases: [(es: String, meaning: String)] = [
        ("¡Soy Proffesssorrro!", "I'm the Proffessorrr!"),
        ("Vamos a ensenar me", "Let's teach… me!"),
        ("no puedo esperar mas", "I can't wait any longer"),
        ("comida buena", "Good food"),
        ("vivo en momento", "I live in the moment"),
        ("Todo es caro", "Everything's expensive"),
        ("Hola bichito", "Hey, creature"),
        ("Fu! Deja lo!!!", "Ugh! Drop it!!!"),
        ("Vamos a la playa", "Let's go to the beach"),
        ("Es un cabrón y narcisista! Como yo.", "He's a jerk and a narcissist! Like me.")
    ]
    @State private var displayedText = ""
    @State private var phraseIndex = 0
    @State private var charIndex = 0
    @State private var isDeleting = false
    @State private var cursorVisible = true
    @State private var typeTask: Task<Void, Never>? = nil
    @State private var showOnboarding = false

    private var showsDog: Bool { level == .top || level == .speaking }

    var body: some View {
        ZStack {
            GameBackground()

            DreamParticlesView()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            GeometryReader { geo in
                let dogH = HomeLayout.dogHeight(geo.size.height)
                let illoH = HomeLayout.illustrationHeight

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: HomeLayout.cardSpacing) {
                        if showsDog {
                            ZStack(alignment: .bottom) {
                                HStack(alignment: .bottom, spacing: 12) {
                                    Image("professor_dog")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: dogH)

                                    speechBubbleView
                                        .padding(.bottom, dogH * 0.50)
                                        .frame(maxWidth: .infinity)
                                }

                                Group { firstCard(illustrationH: illoH) }
                                    .id(level)
                                    .transition(.opacity)
                            }
                            .frame(height: dogH)
                            .transition(.opacity)
                        }

                        remainingCards(illustrationH: illoH)
                    }
                    .padding(.horizontal, HomeLayout.hPadding)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                if level != .top {
                    BackButton { withAnimation(cardTransition) { level = .top } }
                        .padding(.leading, HomeLayout.hPadding)
                        .padding(.top, 56)
                }
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 40)
            .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.08), value: appear)
            .onAppear {
                appear = true
                startTypewriter()
            }
            .onDisappear {
                typeTask?.cancel()
                bubblePlayer?.stop()
                bubblePlayer = nil
            }
        }
        .withBurgerMenu()
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingContainerView {
                showOnboarding = false
            }
            .environment(authState)
        }
        .onChange(of: authState.needsOnboarding) { _, needs in
            if needs { showOnboarding = true }
        }
        .onChange(of: showOnboarding) { _, isShowing in
            if isShowing {
                typeTask?.cancel()
                bubblePlayer?.stop()
                bubblePlayer = nil
                OnboardAudioManager.shared.stop()
                BackgroundMusicPlayer.shared.fadeOut(duration: 0.3)
            } else {
                startTypewriter()
                BackgroundMusicPlayer.shared.play()
            }
        }
        .onAppear {
            if authState.needsOnboarding { showOnboarding = true }
        }
        .fullScreenCover(item: $activeLeaf) { leaf in
            leafDestination(leaf)
        }
        .onChange(of: activeLeaf) { _, leaf in
            if leaf != nil {
                typeTask?.cancel()
                bubblePlayer?.stop()
                bubblePlayer = nil
                let longFade = leaf == .topicFlow || leaf == .streetViewFlow
                BackgroundMusicPlayer.shared.fadeOut(duration: longFade ? 1.5 : 0.3)
            } else if !pendingSessionLaunch {
                // Only resume here if we're actually landing back on this
                // screen — a pending session launch means we're 0.35s away
                // from `launchedSession` taking over, which will stop this
                // right back down again.
                startTypewriter()
                BackgroundMusicPlayer.shared.play()
            }
        }
        .onChange(of: launchedSession) { _, session in
            if session != nil {
                pendingSessionLaunch = false
                typeTask?.cancel()
                bubblePlayer?.stop()
                bubblePlayer = nil
            } else {
                startTypewriter()
                BackgroundMusicPlayer.shared.play()
            }
        }
        .fullScreenCover(item: $launchedSession) { session in
            NavigationStack {
                ChatView(session: session)
            }
            .environment(authState)
            .onAppear { BackgroundMusicPlayer.shared.fadeOut(duration: 1.5) }
            .onDisappear {
                TTSService.shared.stop()
                BackgroundMusicPlayer.shared.play()
            }
        }
    }

    // MARK: - Leaf destinations

    @ViewBuilder
    private func leafDestination(_ leaf: LeafDestination) -> some View {
        switch leaf {
        case .topicFlow:
            if authState.isSignedIn {
                NewSessionView(initialStep: .topicInput, onSessionCreated: handleSessionCreated)
                    .environment(authState)
            } else {
                SignInView().environment(authState)
            }
        case .streetViewFlow:
            if authState.isSignedIn {
                NewSessionView(initialStep: .streetViewPhotos, onSessionCreated: handleSessionCreated)
                    .environment(authState)
            } else {
                SignInView().environment(authState)
            }
        case .rolePlay:
            ComingSoonView(
                title: L("Role Play"),
                message: L("Chat with any character you imagine"),
                systemImage: "theatermasks.fill"
            )
        case .memoryCalendar:
            MemorizeContainerView().environment(authState)
        case .musicPlaceholder:
            if authState.isSignedIn {
                MusicFlowView()
            } else {
                SignInView().environment(authState)
            }
        case .explainRules:
            ComingSoonView(
                title: L("Explain Rules"),
                message: L("browse grammar topics & lessons"),
                systemImage: "text.book.closed.fill"
            )
        case .freeForum:
            ComingSoonView(
                title: L("Ask in a Free Forum"),
                message: L("ask anything, attach a photo"),
                systemImage: "questionmark.bubble.fill"
            )
        }
    }

    private func handleSessionCreated(_ session: LocalChatSession) {
        pendingSessionLaunch = true
        activeLeaf = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            launchedSession = session
        }
    }

    // MARK: - Speech Bubble

    private var speechBubbleView: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.yellow)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            SpeechTailShape()
                .fill(Color.yellow)
                .frame(width: 11, height: 9)
                .offset(x: -10, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayedText + (cursorVisible ? "|" : " "))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)

                Text(L(phrases[phraseIndex].meaning))
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

    // MARK: - Typewriter

    private func playBubbleSound(index: Int) {
        // Localized clip voices the sequence Spanish → native meaning → Spanish.
        // Falls back to the Spanish-only clip if the localized file is missing.
        let langSuffix: String
        switch LocalizationManager.shared.language {
        case .ukrainian: langSuffix = "uk"
        case .english:   langSuffix = "en"
        }
        let localizedName = "dog_bubble_\(index)_\(langSuffix)"
        let url = Bundle.main.url(forResource: localizedName, withExtension: "mp3")
            ?? Bundle.main.url(forResource: "dog_bubble_\(index)", withExtension: "mp3")
        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            bubblePlayer = try AVAudioPlayer(contentsOf: url)
            bubblePlayer?.volume = 0.7
            bubblePlayer?.play()
        } catch {}
    }

    private func startTypewriter() {
        typeTask?.cancel()
        displayedText = ""
        phraseIndex = 0
        charIndex = 0
        isDeleting = false

        typeTask = Task {
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run { cursorVisible.toggle() }
                }
            }

            // One phrase at a time: each bubble is spoken (Spanish → meaning →
            // Spanish) and the visible text is held for the whole clip, so the
            // audio is the source of truth and cycles never overlap.
            while !Task.isCancelled {
                let phrase = phrases[phraseIndex].es

                // Start this phrase's clip and learn how long it runs.
                let duration = await MainActor.run { () -> TimeInterval in
                    playBubbleSound(index: phraseIndex)
                    return bubblePlayer?.duration ?? 0
                }

                // Type the Spanish in.
                await MainActor.run { charIndex = 0; displayedText = "" }
                while charIndex < phrase.count && !Task.isCancelled {
                    await MainActor.run {
                        charIndex += 1
                        displayedText = String(phrase.prefix(charIndex))
                    }
                    try? await Task.sleep(nanoseconds: 70_000_000)
                }

                // Hold the fully-typed phrase until its clip finishes playing.
                let start = Date()
                let minHold: TimeInterval = 2.2
                let cap = max(duration, minHold) + 0.5
                while !Task.isCancelled {
                    let playing = await MainActor.run { bubblePlayer?.isPlaying ?? false }
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed >= cap { break }
                    if !playing && elapsed >= minHold { break }
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }

                // Delete before moving to the next phrase.
                while charIndex > 0 && !Task.isCancelled {
                    await MainActor.run {
                        charIndex -= 1
                        displayedText = String(phrase.prefix(charIndex))
                    }
                    try? await Task.sleep(nanoseconds: 32_000_000)
                }

                await MainActor.run { phraseIndex = (phraseIndex + 1) % phrases.count }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    // MARK: - Card layout per level

    @ViewBuilder
    private func firstCard(illustrationH: CGFloat) -> some View {
        switch level {
        case .top:
            speakingCard(illustrationH: illustrationH)
        case .speaking:
            learnFromWhatYouSeeCard(illustrationH: illustrationH)
        case .memory, .grammar:
            EmptyView()
        }
    }

    @ViewBuilder
    private func remainingCards(illustrationH: CGFloat) -> some View {
        Group {
            switch level {
            case .top:
                memoryCard(illustrationH: illustrationH)
                grammarCard(illustrationH: illustrationH)
            case .speaking:
                rolePlayCard(illustrationH: illustrationH)
                yourTopicCard(illustrationH: illustrationH)
            case .memory:
                calendarCard(illustrationH: illustrationH)
                musicCard(illustrationH: illustrationH)
            case .grammar:
                explainRulesCard(illustrationH: illustrationH)
                verbsTimesCard(illustrationH: illustrationH)
                freeForumCard(illustrationH: illustrationH)
            }
        }
        .id(level)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Top-level cards

    private func speakingCard(illustrationH: CGFloat) -> some View {
        Button(action: { withAnimation(cardTransition) { level = .speaking } }) {
            HomeModeCard(
                title: L("Speaking"),
                subtitle: L("practice real conversations & role play"),
                pressed: speakingCardPressed
            ) {
                Image("btn_speaking")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in speakingCardPressed = true }
                .onEnded { _ in speakingCardPressed = false }
        )
    }

    private func memoryCard(illustrationH: CGFloat) -> some View {
        Button(action: { withAnimation(cardTransition) { level = .memory } }) {
            HomeModeCard(
                title: L("Memory"),
                subtitle: L("your word queue & memory games"),
                badge: memorizeDueCount,
                pressed: memoryCardPressed
            ) {
                Image("btn_memory")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in memoryCardPressed = true }
                .onEnded { _ in memoryCardPressed = false }
        )
    }

    private func grammarCard(illustrationH: CGFloat) -> some View {
        Button(action: { withAnimation(cardTransition) { level = .grammar } }) {
            HomeModeCard(
                title: L("Grammar"),
                subtitle: L("rules, verbs & tenses explained"),
                pressed: grammarCardPressed
            ) {
                Image("btn_grammar")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in grammarCardPressed = true }
                .onEnded { _ in grammarCardPressed = false }
        )
    }

    // MARK: - Speaking level cards

    private func learnFromWhatYouSeeCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .streetViewFlow }) {
            HomeModeCard(
                title: L("Learn from what you see"),
                subtitle: L("Take a picture of what you see around you"),
                pressed: speakingCardPressed
            ) {
                Image("btn_eye_see")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in speakingCardPressed = true }
                .onEnded { _ in speakingCardPressed = false }
        )
    }

    private func rolePlayCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .rolePlay }) {
            HomeModeCard(
                title: L("Role Play"),
                subtitle: L("Chat with any character you imagine"),
                pressed: rolePlayCardPressed
            ) {
                Image("btn_role_play")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in rolePlayCardPressed = true }
                .onEnded { _ in rolePlayCardPressed = false }
        )
    }

    private func yourTopicCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .topicFlow }) {
            HomeModeCard(
                title: L("Your topic"),
                subtitle: L("Talk with tutor via text and voice messages"),
                pressed: yourTopicCardPressed
            ) {
                Image("btn_parrot_brain")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in yourTopicCardPressed = true }
                .onEnded { _ in yourTopicCardPressed = false }
        )
    }

    // MARK: - Memory level cards

    private func calendarCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .memoryCalendar }) {
            HomeModeCard(
                title: L("Your Words Calendar"),
                subtitle: L("everyday queue for new words"),
                badge: memorizeDueCount,
                pressed: calendarCardPressed
            ) {
                Image("btn_words_calendar")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in calendarCardPressed = true }
                .onEnded { _ in calendarCardPressed = false }
        )
    }

    private func musicCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .musicPlaceholder }) {
            HomeModeCard(
                title: L("Remember with Music"),
                subtitle: L("learn vocabulary through songs"),
                pressed: musicCardPressed
            ) {
                Image("btn_remember_music")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in musicCardPressed = true }
                .onEnded { _ in musicCardPressed = false }
        )
    }

    // MARK: - Grammar level cards

    private func explainRulesCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .explainRules }) {
            HomeModeCard(
                title: L("Explain Rules"),
                subtitle: L("browse grammar topics & lessons"),
                pressed: explainRulesCardPressed
            ) {
                Image("btn_explain_rules")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in explainRulesCardPressed = true }
                .onEnded { _ in explainRulesCardPressed = false }
        )
    }

    private func verbsTimesCard(illustrationH: CGFloat) -> some View {
        Button(action: onVerbGame) {
            HomeModeCard(
                title: L("Verbs & times"),
                subtitle: L("game to learn verbs & tenses fast"),
                pressed: verbsTimesCardPressed
            ) {
                Image("btn_verbs_times")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in verbsTimesCardPressed = true }
                .onEnded { _ in verbsTimesCardPressed = false }
        )
    }

    private func freeForumCard(illustrationH: CGFloat) -> some View {
        Button(action: { activeLeaf = .freeForum }) {
            HomeModeCard(
                title: L("Ask in a Free Forum"),
                subtitle: L("ask anything, attach a photo"),
                pressed: freeForumCardPressed
            ) {
                Image("btn_free_forum")
                    .resizable()
                    .scaledToFit()
                    .frame(height: illustrationH)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in freeForumCardPressed = true }
                .onEnded { _ in freeForumCardPressed = false }
        )
    }

    private var memorizeDueCount: Int {
        MemoryCardService(context: modelContext).dueCount()
    }
}

// MARK: - Dream Particles

struct DreamParticle: Identifiable {
    let id: Int
    let imageName: String
    let size: CGFloat
    let angleDeg: Double
    let maxDistance: CGFloat
    let curvature: CGFloat
    let totalRotationDeg: Double
    let duration: Double
    let activeFraction: Double
    let delay: Double
}

struct DreamParticlesView: View {
    private let particles: [DreamParticle] = [
        DreamParticle(id:  0, imageName: "dream_hotdog",          size: 108, angleDeg:  -55, maxDistance: 240, curvature:  20, totalRotationDeg:  130, duration: 32.0, activeFraction: 0.30, delay:  0.0),
        DreamParticle(id:  1, imageName: "dream_pasta",           size: 122, angleDeg:  -28, maxDistance: 355, curvature:  22, totalRotationDeg:  -98, duration: 32.0, activeFraction: 0.30, delay:  2.5),
        DreamParticle(id:  2, imageName: "dream_chicken_fried",   size: 104, angleDeg:    2, maxDistance: 318, curvature:  36, totalRotationDeg:  110, duration: 32.0, activeFraction: 0.30, delay:  5.0),
        DreamParticle(id:  3, imageName: "dream_chicken_roasted", size: 114, angleDeg:   26, maxDistance: 410, curvature: -28, totalRotationDeg:  -90, duration: 32.0, activeFraction: 0.30, delay:  7.5),
        DreamParticle(id:  4, imageName: "dream_grilled_meat",    size: 126, angleDeg:   52, maxDistance: 570, curvature:  30, totalRotationDeg:  120, duration: 32.0, activeFraction: 0.30, delay: 10.0),
        DreamParticle(id:  5, imageName: "dream_cheese",          size:  98, angleDeg:   70, maxDistance: 715, curvature: -28, totalRotationDeg: -110, duration: 32.0, activeFraction: 0.30, delay: 12.5),
        DreamParticle(id:  6, imageName: "dream_books",           size: 116, angleDeg:   90, maxDistance: 720, curvature:  26, totalRotationDeg:   94, duration: 32.0, activeFraction: 0.30, delay: 15.0),
        DreamParticle(id:  7, imageName: "dream_spanish_book",    size: 110, angleDeg:  108, maxDistance: 700, curvature: -24, totalRotationDeg: -120, duration: 32.0, activeFraction: 0.30, delay: 17.5),
        DreamParticle(id:  8, imageName: "dream_espanol_books",   size: 118, angleDeg:  322, maxDistance: 310, curvature:  32, totalRotationDeg:  102, duration: 32.0, activeFraction: 0.30, delay: 20.0),
        DreamParticle(id:  9, imageName: "dream_kitten",          size: 120, angleDeg:  -80, maxDistance: 290, curvature: -30, totalRotationDeg:  -85, duration: 32.0, activeFraction: 0.30, delay: 22.5),
        DreamParticle(id: 10, imageName: "dream_stick",           size: 130, angleDeg:  135, maxDistance: 660, curvature:  22, totalRotationDeg:  150, duration: 32.0, activeFraction: 0.30, delay: 25.0),
        DreamParticle(id: 11, imageName: "dream_seagull",         size: 112, angleDeg:  -15, maxDistance: 380, curvature: -18, totalRotationDeg:   75, duration: 32.0, activeFraction: 0.30, delay: 27.5),
        DreamParticle(id: 12, imageName: "dream_dollar",          size: 124, angleDeg:  160, maxDistance: 580, curvature:  24, totalRotationDeg: -105, duration: 32.0, activeFraction: 0.30, delay: 30.0),
    ]

    var body: some View {
        GeometryReader { geo in
            let originX = geo.size.width  * 0.22
            let originY = geo.size.height * 0.20
            ForEach(particles) { p in
                DreamParticleItemView(
                    particle: p,
                    originX: originX,
                    originY: originY
                )
            }
        }
    }
}

struct DreamParticleItemView: View {
    let particle: DreamParticle
    let originX: CGFloat
    let originY: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t          = context.date.timeIntervalSinceReferenceDate + particle.delay
            let totalPhase = t.truncatingRemainder(dividingBy: particle.duration) / particle.duration
            let af         = particle.activeFraction
            let isResting  = totalPhase >= af
            let phase      = isResting ? 1.0 : (totalPhase / af)

            let pos = computePosition(phase: CGFloat(phase))
            let sc  = computeScale(phase: phase)
            let op  = isResting ? 0.0 : computeOpacity(phase: phase)
            let rot = computeRotation(phase: phase)

            Image(particle.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: particle.size * CGFloat(sc))
                .rotationEffect(.degrees(rot))
                .opacity(op)
                .position(x: pos.x, y: pos.y)
        }
    }

    private func computePosition(phase: CGFloat) -> CGPoint {
        let rad  = CGFloat(particle.angleDeg) * .pi / 180.0
        let t    = phase
        let main = particle.maxDistance * t
        let bump = particle.curvature * t * (1 - t) * 4
        return CGPoint(
            x: originX + cos(rad) * main + (-sin(rad)) * bump,
            y: originY + sin(rad) * main +   cos(rad)  * bump
        )
    }

    private func computeScale(phase: Double) -> Double {
        if phase < 0.22 {
            return (phase / 0.22) * 1.12
        } else if phase < 0.30 {
            return 1.12 - (phase - 0.22) / 0.08 * 0.12
        } else if phase < 0.74 {
            return 1.0
        } else {
            return max(0.35, 1.0 - (phase - 0.74) / 0.26 * 0.65)
        }
    }

    private func computeOpacity(phase: Double) -> Double {
        if phase < 0.10 {
            return phase / 0.10
        } else if phase < 0.76 {
            return 1.0
        } else {
            return max(0, 1.0 - (phase - 0.76) / 0.24)
        }
    }

    private func computeRotation(phase: Double) -> Double {
        phase * particle.totalRotationDeg
    }
}

struct SpeechTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
