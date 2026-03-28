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
    @Binding var timerSeconds: Double
    @Binding var selectedTense: Tense

    @State private var displayedText: String = ""
    @State private var cursorVisible: Bool = true
    @State private var isDone: Bool = false
    @State private var typingTask: Task<Void, Never>? = nil
    @State private var showSettings: Bool = false
    @State private var chosenPhrase: TypewriterPhrase? = nil
    @State private var visibleVocabCount: Int = 0

    private var maxVocabCount: Int { chosenPhrase?.vocabulary.count ?? 0 }
    private var tapHintText: String {
        if !isDone { return "tap to skip" }
        return "tap anywhere to continue"
    }

    private static let phrases: [TypewriterPhrase] = loadPhrases()

    static func loadPhrases() -> [TypewriterPhrase] {
        guard let url = Bundle.main.url(forResource: "phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TypewriterPhrase].self, from: data) else {
            return [TypewriterPhrase(
                base: "You decided to learn Spanish. This could change everything, and you might ",
                lightEnding: "become fluent by summer.",
                darkEnding: "still be on lesson three by Christmas.",
                vocabulary: []
            )]
        }
        return decoded
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topHalf(height: geo.size.height / 2)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)

                    bottomHalf(height: geo.size.height / 2)
                }
            }
        }
        .onTapGesture { handleTap() }
        .onAppear {
            startTyping()
            startCursorBlink()
        }
        .onDisappear { typingTask?.cancel() }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(timerSeconds: $timerSeconds, selectedTense: $selectedTense)
        }
    }

    private func topHalf(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                Text(displayedAttributedText)
                    .font(.system(size: 19, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: height)

            Button { showSettings = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(20)
            }
        }
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder
    private func bottomHalf(height: CGFloat) -> some View {
        if isLandscape {
            VStack(spacing: 0) {
                if isDone, let phrase = chosenPhrase, !phrase.vocabulary.isEmpty {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(phrase.vocabulary.prefix(visibleVocabCount).enumerated()), id: \.offset) { _, word in
                            vocabWordView(word: word, fontSize: 13, spanishSize: 15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                Spacer(minLength: 0)

                Text(tapHintText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .animation(.easeInOut(duration: 0.3), value: tapHintText)
                    .padding(.bottom, 14)
            }
            .frame(height: height)
        } else {
            ZStack(alignment: .bottom) {
                if isDone, let phrase = chosenPhrase, !phrase.vocabulary.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: 24)
                            ForEach(Array(phrase.vocabulary.prefix(visibleVocabCount).enumerated()), id: \.offset) { idx, word in
                                vocabWordView(word: word, fontSize: 15, spanishSize: 17)
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, idx < phrase.vocabulary.count - 1 ? 20 : 0)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            Spacer().frame(height: 56)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                Text(tapHintText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .animation(.easeInOut(duration: 0.3), value: tapHintText)
                    .padding(.bottom, 24)
            }
            .frame(height: height)
        }
    }

    private func vocabWordView(word: VocabWord, fontSize: CGFloat, spanishSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(word.english)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Text("  →  ")
                    .font(.system(size: fontSize - 2, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Text(word.spanish)
                    .font(.system(size: spanishSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.4), radius: 4)
            }
            ForEach(word.examples, id: \.self) { example in
                Text("• \(example)")
                    .font(.system(size: fontSize - 3, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .lineSpacing(3)
            }
        }
    }

    private var displayedAttributedText: AttributedString {
        var base = AttributedString(displayedText)
        base.foregroundColor = .white
        var cursor = AttributedString("|")
        cursor.foregroundColor = cursorVisible ? .yellow : .clear
        return base + cursor
    }

    private func handleTap() {
        if !isDone {
            // Tap 1: skip typing, show full dark ending, auto-reveal examples
            typingTask?.cancel()
            if let phrase = chosenPhrase {
                displayedText = phrase.base + phrase.darkEnding
            }
            finishTyping()
        } else {
            // Tap 2: navigate
            onContinue()
        }
    }

    private func finishTyping() {
        isDone = true
        scheduleVocabReveal()
    }

    private func scheduleVocabReveal() {
        guard let phrase = chosenPhrase else { return }
        let count = phrase.vocabulary.count
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.6) {
                withAnimation(.easeOut(duration: 0.4)) {
                    if visibleVocabCount < i + 1 {
                        visibleVocabCount = i + 1
                    }
                }
            }
        }
    }

    private func startTyping() {
        let phrase = Self.phrases.randomElement() ?? Self.phrases[0]
        chosenPhrase = phrase
        displayedText = ""
        visibleVocabCount = 0
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

    private func typingDelay(for char: Character) -> Double {
        if ".!?".contains(char) { return Double.random(in: 0.22...0.50) }
        if ",;:".contains(char) { return Double.random(in: 0.10...0.22) }
        if char == " " && Int.random(in: 0...6) == 0 { return Double.random(in: 0.15...0.40) }
        return Double.random(in: 0.04...0.10)
    }
}

struct SettingsSheetView: View {
    @Binding var timerSeconds: Double
    @Binding var selectedTense: Tense
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Tense", systemImage: "book.closed.fill")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.gray)
                        Picker("Tense", selection: $selectedTense) {
                            ForEach(Tense.allCases) { tense in
                                Text(tense.displayLabel).tag(tense)
                            }
                        }
                        .pickerStyle(.segmented)
                        .colorMultiply(.yellow)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Timer per word", systemImage: "timer")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.1fs", timerSeconds))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                        Slider(value: $timerSeconds, in: 1.0...8.0, step: 0.5)
                            .accentColor(.yellow)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.yellow)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
