import SwiftUI

struct VocabWord: Codable {
    let english: String
    let spanish: String
    let examples: [String]
}

struct TypewriterPhrase: Codable {
    let base: String
    let lightEnding: String
    let darkEnding: String
    let vocabulary: [VocabWord]
}

struct TypewriterIntroView: View {
    let onContinue: () -> Void

    @State private var displayedText: String = ""
    @State private var cursorVisible: Bool = true
    @State private var isDone: Bool = false
    @State private var typingTask: Task<Void, Never>? = nil
    @State private var chosenPhrase: TypewriterPhrase? = nil
    @State private var cardAppear: Bool = false
    @State private var glowPulse: Bool = false

    private static let phrases: [TypewriterPhrase] = loadPhrases()

    static func loadPhrases() -> [TypewriterPhrase] {
        guard let url = Bundle.main.url(forResource: "phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TypewriterPhrase].self, from: data) else {
            return [TypewriterPhrase(
                base: L("You decided to learn Spanish. This could change everything, and you might "),
                lightEnding: L("become fluent by summer."),
                darkEnding: L("still be on lesson three by Christmas."),
                vocabulary: []
            )]
        }
        // The motivational intro copy (base/light/dark endings) is UI chrome and
        // is localized via L(); the vocabulary stays Spanish learning content.
        return decoded.map { phrase in
            TypewriterPhrase(
                base: L(phrase.base),
                lightEnding: L(phrase.lightEnding),
                darkEnding: L(phrase.darkEnding),
                vocabulary: phrase.vocabulary
            )
        }
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            GameBackground()

            DreamParticlesView()
                .allowsHitTesting(false)

            GeometryReader { geo in
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top + 30)

                    Spacer(minLength: 0)

                    dogAndQuoteSection(geo: geo)
                        .padding(.horizontal, isLandscape ? 48 : 20)
                        .opacity(cardAppear ? 1 : 0)
                        .scaleEffect(cardAppear ? 1 : 0.96)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: cardAppear)

                    Spacer(minLength: 0)

                    Color.clear.frame(height: geo.safeAreaInsets.bottom + 20)
                }
            }
        }
        .ignoresSafeArea()
        .onTapGesture { handleTap() }
        .onAppear {
            cardAppear = true
            startTyping()
            startCursorBlink()
            startGlowPulse()
        }
        .onDisappear { typingTask?.cancel() }
    }

    // MARK: - Dog + Quote Section

    private func dogAndQuoteSection(geo: GeometryProxy) -> some View {
        let cardHeight: CGFloat = isLandscape
            ? min(geo.size.height * 0.60, 220.0)
            : min(geo.size.height * 0.48, 300.0)
        let dogHeight: CGFloat = isLandscape ? 330 : 450
        let dogVisibleAbove: CGFloat = isLandscape ? 170 : 230

        return ZStack(alignment: .topLeading) {
            Image("professor_dog")
                .resizable()
                .scaledToFit()
                .frame(height: dogHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

            quoteCard(geo: geo, cardHeight: cardHeight)
                .padding(.top, dogVisibleAbove)
        }
        .frame(height: cardHeight + dogVisibleAbove)
    }

    // MARK: - Quote Card

    private func quoteCard(geo: GeometryProxy, cardHeight: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.07, green: 0.06, blue: 0.18).opacity(0.88),
                            Color(red: 0.07, green: 0.06, blue: 0.18).opacity(0.94)
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.55)
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.yellow.opacity(glowPulse && !isDone ? 0.45 : 0.18),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(
                    color: Color.yellow.opacity(glowPulse && !isDone ? 0.14 : 0.04),
                    radius: 28
                )
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glowPulse)

            VStack(alignment: .leading, spacing: 0) {
                Text("\"")
                    .font(.system(size: 40, weight: .black, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.25))
                    .padding(.leading, 4)
                    .padding(.top, -8)

                Text(displayedAttributedText)
                    .font(.system(size: isLandscape ? 15 : 17, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Text("\"")
                    .font(.system(size: 40, weight: .black, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                    .padding(.bottom, -8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
    }

    // MARK: - Attributed text

    private var displayedAttributedText: AttributedString {
        var base = AttributedString(displayedText)
        base.foregroundColor = .white
        var cursor = AttributedString("|")
        cursor.foregroundColor = cursorVisible ? Color.yellow : Color.clear
        return base + cursor
    }

    // MARK: - Logic

    private func handleTap() {
        if !isDone {
            typingTask?.cancel()
            if let phrase = chosenPhrase {
                displayedText = phrase.base + phrase.darkEnding
            }
            finishTyping()
        } else {
            onContinue()
        }
    }

    private func finishTyping() {
        isDone = true
    }

    private func startTyping() {
        let phrase = Self.phrases.randomElement() ?? Self.phrases[0]
        chosenPhrase = phrase
        displayedText = ""
        typingTask = Task {
            for char in phrase.base + phrase.lightEnding {
                guard !Task.isCancelled else { return }
                await MainActor.run { displayedText.append(char) }
                try? await Task.sleep(nanoseconds: UInt64(typingDelay(for: char) * 1_000_000_000))
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            for _ in phrase.lightEnding {
                guard !Task.isCancelled else { return }
                await MainActor.run { if !displayedText.isEmpty { displayedText.removeLast() } }
                try? await Task.sleep(nanoseconds: 32_000_000)
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            for char in phrase.darkEnding {
                guard !Task.isCancelled else { return }
                await MainActor.run { displayedText.append(char) }
                try? await Task.sleep(nanoseconds: UInt64(typingDelay(for: char) * 1_000_000_000))
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run { finishTyping() }
        }
    }

    private func startCursorBlink() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 520_000_000)
                await MainActor.run { cursorVisible.toggle() }
            }
        }
    }

    private func startGlowPulse() {
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run { glowPulse = true }
        }
    }

    private func typingDelay(for char: Character) -> Double {
        if ".!?".contains(char) { return Double.random(in: 0.22...0.50) }
        if ",;:".contains(char) { return Double.random(in: 0.10...0.22) }
        if char == " " && Int.random(in: 0...6) == 0 { return Double.random(in: 0.15...0.40) }
        return Double.random(in: 0.04...0.10)
    }
}

/// Standalone in-game settings sheet for the verb game (opened from the game's
/// gear button). Wraps the shared, restyled `VerbGameSettingsView` — the same
/// page reachable from Settings → Verbs & times — in its own NavigationStack so
/// it presents cleanly as a sheet with a Done button.
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VerbGameSettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
