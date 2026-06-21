import SwiftUI

struct ModeSelectorView: View {
    let onVerbGame: () -> Void
    @State private var showChat = false
    @State private var showMemorize = false
    @State private var appear = false
    @State private var verbCardPressed = false
    @State private var chatCardPressed = false
    @State private var memorizeCardPressed = false
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext

    private let phrases = [
        "¡Soy Proffesssorrro!",
        "Vamos a ensenar me",
        "no puedo esperar mas",
        "comida buena",
        "vivo en momento",
        "Todo es caro",
        "¿Qué tal, bichito?",
        "Fu! Deja lo!!!",
        "Vamos a la playa",
        "Es un cabrón y narcisista! Como yo."
    ]
    @State private var displayedText = ""
    @State private var phraseIndex = 0
    @State private var charIndex = 0
    @State private var isDeleting = false
    @State private var cursorVisible = true
    @State private var typeTask: Task<Void, Never>? = nil

    private let tileHeight: CGFloat = 86

    var body: some View {
        ZStack {
            GameBackground()

            DreamParticlesView()
                .allowsHitTesting(false)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top + 30)

                    Spacer(minLength: 6)

                    dogAndChatCardSection(geo: geo)

                    Spacer(minLength: 12)

                    verbGameCard
                        .padding(.horizontal, 20)

                    Spacer(minLength: 8)

                    memorizeCard
                        .padding(.horizontal, 20)

                    Spacer(minLength: 8)

                    Color.clear.frame(height: geo.safeAreaInsets.bottom + 16)
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
            }
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showChat) {
            chatDestination
        }
        .fullScreenCover(isPresented: $showMemorize) {
            MemorizeContainerView()
        }
    }

    // MARK: - Dog + Chat Card ZStack

    private func dogAndChatCardSection(geo: GeometryProxy) -> some View {
        let dogHeight: CGFloat = 370
        let dogVisibleAboveCard: CGFloat = 210

        return ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom, spacing: 14) {
                Image("professor_dog")
                    .resizable()
                    .scaledToFit()
                    .frame(height: dogHeight)

                speechBubbleView
                    .padding(.bottom, 215)
            }
            .padding(.horizontal, 20)

            chatTutorCard
                .padding(.horizontal, 20)
                .padding(.top, dogVisibleAboveCard)
        }
        .frame(height: tileHeight + dogVisibleAboveCard)
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

            Text(displayedText + (cursorVisible ? "|" : " "))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86)
    }

    // MARK: - Typewriter

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

            while !Task.isCancelled {
                let phrase = phrases[phraseIndex]

                if !isDeleting {
                    if charIndex < phrase.count {
                        await MainActor.run {
                            charIndex += 1
                            displayedText = String(phrase.prefix(charIndex))
                        }
                        try? await Task.sleep(nanoseconds: 70_000_000)
                    } else {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        await MainActor.run { isDeleting = true }
                    }
                } else {
                    if charIndex > 0 {
                        await MainActor.run {
                            charIndex -= 1
                            displayedText = String(phrase.prefix(charIndex))
                        }
                        try? await Task.sleep(nanoseconds: 32_000_000)
                    } else {
                        await MainActor.run {
                            isDeleting = false
                            phraseIndex = (phraseIndex + 1) % phrases.count
                        }
                        try? await Task.sleep(nanoseconds: 380_000_000)
                    }
                }
            }
        }
    }

    // MARK: - Cards

    private var chatTutorCard: some View {
        Button(action: { showChat = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.58, blue: 1.0),
                                Color(red: 0.06, green: 0.38, blue: 0.90),
                                Color(red: 0.04, green: 0.22, blue: 0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)

                HStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white.opacity(0.65))
                        .shadow(color: .cyan.opacity(0.6), radius: 8)

                    Text("CHAT TUTOR")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(1)

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .scaleEffect(chatCardPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: chatCardPressed)
            .shadow(color: Color.blue.opacity(0.45), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in chatCardPressed = true }
                .onEnded { _ in chatCardPressed = false }
        )
    }

    private var verbGameCard: some View {
        Button(action: onVerbGame) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.82, blue: 0.08),
                                Color(red: 0.88, green: 0.60, blue: 0.02),
                                Color(red: 0.72, green: 0.42, blue: 0.01)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.30), lineWidth: 1.5)

                HStack(spacing: 14) {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black.opacity(0.55))

                    Text("VERB GAME")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.black.opacity(0.80))
                        .tracking(1)

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .scaleEffect(verbCardPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: verbCardPressed)
            .shadow(color: Color.yellow.opacity(0.45), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in verbCardPressed = true }
                .onEnded { _ in verbCardPressed = false }
        )
    }

    private var memorizeDueCount: Int {
        MemoryCardService(context: modelContext).dueCount()
    }

    private var memorizeCard: some View {
        Button(action: { showMemorize = true }) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.78, blue: 0.52),
                                Color(red: 0.10, green: 0.58, blue: 0.40),
                                Color(red: 0.04, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)

                HStack(spacing: 14) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .shadow(color: .green.opacity(0.6), radius: 8)

                    Text("LORO MEMORIZE")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(1)

                    Spacer()

                    if memorizeDueCount > 0 {
                        Text("\(memorizeDueCount)")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.yellow)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)
            .scaleEffect(memorizeCardPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: memorizeCardPressed)
            .shadow(color: Color.green.opacity(0.40), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in memorizeCardPressed = true }
                .onEnded { _ in memorizeCardPressed = false }
        )
    }

    // MARK: - Chat Destination

    @ViewBuilder
    private var chatDestination: some View {
        if authState.isSignedIn {
            SessionListView()
                .environment(authState)
        } else {
            SignInView()
                .environment(authState)
        }
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
    let duration: Double          // total cycle length (active travel + invisible rest)
    let activeFraction: Double    // fraction of duration that's the visible travel phase
    let delay: Double
}

struct DreamParticlesView: View {
    // Each particle has a 32-second total cycle; it travels/is-visible for the first
    // activeFraction (≈30%) of that cycle, then rests invisible.
    // With 13 particles and delays spread 2.5 s apart, at most ≈4 are visible at once.
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
