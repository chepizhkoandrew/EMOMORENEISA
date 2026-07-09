import SwiftUI
import SwiftData
import AVFoundation

private let parrotWordSynth = AVSpeechSynthesizer()

struct ParrotWordGridView: View {
    let message: LocalChatMessage
    let sessionId: UUID
    let level: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPhrases: [ParrotPhrase]

    @State private var tokens: [WordToken] = []
    @State private var pickedIndices: [Int] = []
    @State private var repeatCount: Int = 4
    @State private var showPlayer = false
    @State private var activePhrase: ParrotPhrase? = nil
    @State private var replayPhrase: ParrotPhrase? = nil
    @Namespace private var chipNS

    private let maxPicks = 6

    struct WordToken: Identifiable {
        let id: Int
        let text: String
    }

    init(message: LocalChatMessage, sessionId: UUID, level: String) {
        self.message = message
        self.sessionId = sessionId
        self.level = level
        let mid = message.id
        _existingPhrases = Query(
            filter: #Predicate<ParrotPhrase> { $0.messageId == mid },
            sort: \.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    if !existingPhrases.isEmpty {
                        existingParrotsList
                        Divider().background(AppColors.cardBorder)
                    }
                    phraseBar
                    Divider().background(AppColors.cardBorder)
                    wordGrid
                    Spacer(minLength: 0)
                    bottomBar
                }
            }
            .navigationTitle(L("Seagull Steven"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
        }
        .onAppear { buildTokens() }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: resetSelection) {
            if let phrase = activePhrase {
                ParrotPlayerView(
                    phrase: phrase,
                    initialLoops: repeatCount,
                    messageText: message.textContent
                )
                .environment(\.modelContext, modelContext)
            }
        }
        .fullScreenCover(item: $replayPhrase) { phrase in
            ParrotReplayView(phrase: phrase) {
                deletePhrase(phrase)
            }
            .environment(\.modelContext, modelContext)
        }
    }

    // MARK: - Existing Parrots

    private var existingParrotsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Saved Parrots"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(existingPhrases) { phrase in
                        existingPhraseCard(phrase)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
        }
        .background(AppColors.backgroundTop)
    }

    private func existingPhraseCard(_ phrase: ParrotPhrase) -> some View {
        HStack(spacing: 10) {
            Button {
                replayPhrase = phrase
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phrase.spanishPhrase.isEmpty ? phrase.selectedWords.joined(separator: " ") : phrase.spanishPhrase)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    if !phrase.englishTranslation.isEmpty {
                        Text(phrase.englishTranslation)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 160, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    activePhrase = phrase
                    showPlayer = true
                } label: {
                    Image(systemName: phrase.hasAudio ? "play.circle.fill" : "arrow.clockwise.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.yellow)
                }

                Button(role: .destructive) {
                    deletePhrase(phrase)
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    // MARK: - Phrase Bar

    private var phraseBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(existingPhrases.isEmpty ? L("Your phrase") : L("New phrase"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            if pickedIndices.isEmpty {
                Text(L("Tap words below to build a phrase"))
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pickedIndices, id: \.self) { idx in
                            let token = tokens[idx]
                            Button {
                                unpick(index: idx)
                            } label: {
                                Text(token.text)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.yellow)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .matchedGeometryEffect(id: "chip_\(idx)", in: chipNS)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(AppColors.backgroundTop)
    }

    // MARK: - Word Grid

    private var wordGrid: some View {
        ScrollView {
            FlowLayout(hSpacing: 10, vSpacing: 10) {
                ForEach(tokens) { token in
                    let isPicked = pickedIndices.contains(token.id)
                    Button {
                        if isPicked {
                            unpick(index: token.id)
                        } else {
                            pick(index: token.id)
                            speakSpanishWord(token.text)
                        }
                    } label: {
                        Text(token.text)
                            .font(.system(size: 18, weight: isPicked ? .semibold : .regular, design: .rounded))
                            .foregroundColor(isPicked ? Color.yellow.opacity(0.4) : AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isPicked ? Color.yellow.opacity(0.08) : AppColors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isPicked ? Color.yellow.opacity(0.3) : AppColors.cardBorder, lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .matchedGeometryEffect(id: "chip_\(token.id)", in: chipNS, isSource: !isPicked)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPicked)
                    .disabled(isPicked == false && pickedIndices.count >= maxPicks)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L("Repeat"))
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                HStack(spacing: 0) {
                    ForEach([1, 2, 4, 6, 8, 10, 20], id: \.self) { n in
                        Button {
                            repeatCount = n
                        } label: {
                            Text("\(n)×")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(repeatCount == n ? .black : AppColors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(repeatCount == n ? Color.yellow : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)

            Button(action: startParrot) {
                HStack(spacing: 10) {
                    Image("icon_beak")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(L("Talk to Seagull Steven"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(pickedIndices.isEmpty ? Color.yellow.opacity(0.3) : Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .disabled(pickedIndices.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    // MARK: - Helpers

    private func speakSpanishWord(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.38
        utterance.volume = 1.0
        parrotWordSynth.stopSpeaking(at: .immediate)
        parrotWordSynth.speak(utterance)
    }

    private func buildTokens() {
        guard let text = message.textContent else { return }
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        tokens = words.enumerated().map { WordToken(id: $0.offset, text: $0.element) }
    }

    private func pick(index: Int) {
        guard !pickedIndices.contains(index), pickedIndices.count < maxPicks else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            pickedIndices.append(index)
        }
    }

    private func unpick(index: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            pickedIndices.removeAll { $0 == index }
        }
    }

    private func startParrot() {
        guard !pickedIndices.isEmpty else { return }
        let words = pickedIndices.map { tokens[$0].text }
        let phrase = ParrotPhrase(
            messageId: message.id,
            sessionId: sessionId,
            selectedWords: words,
            spanishPhrase: words.joined(separator: " "),
            englishTranslation: ""
        )
        modelContext.insert(phrase)
        try? modelContext.save()
        activePhrase = phrase
        showPlayer = true
    }

    // Clear the picked words when the player closes so the grid is ready for a
    // fresh phrase — otherwise the previous selection stays highlighted and the
    // user has to manually deselect before picking another phrase.
    private func resetSelection() {
        activePhrase = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            pickedIndices.removeAll()
        }
    }

    private func deletePhrase(_ phrase: ParrotPhrase) {
        for path in phrase.segmentPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        let dir = ParrotPhrase.parrotDir(for: phrase.id)
        try? FileManager.default.removeItem(at: dir)
        modelContext.delete(phrase)
        try? modelContext.save()
    }
}

/// Lightweight replay modal for a saved parrot — mirrors the memory-queue's
/// `VocabularyReplayView` (illustration + phrase + translation, auto-plays once)
/// so tapping a Saved Parrot card feels consistent with the Loro memory queue.
struct ParrotReplayView: View {
    let phrase: ParrotPhrase
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player = LoopingParrotPlayer()
    @State private var service = ParrotService()
    @State private var usingTTS: Bool = false
    @State private var showDeleteConfirmation = false

    private var title: String {
        phrase.spanishPhrase.isEmpty ? phrase.selectedWords.joined(separator: " ") : phrase.spanishPhrase
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                HStack {
                    BackButton {
                        stopPlayback()
                        dismiss()
                    }
                    Spacer()
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(12)
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal, 12)

                LoroIllustrationView(url: phrase.illustrationURL, fallback: .listening, size: 160)
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                if !phrase.englishTranslation.isEmpty {
                    Text(phrase.englishTranslation)
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
            if phrase.hasAudio {
                player.start(phrase: phrase, loops: 1)
            } else {
                usingTTS = true
                TTSService.shared.speak(text: title, messageId: phrase.id, context: "loro")
            }
            await service.ensureIllustration(for: phrase)
        }
        .onDisappear { stopPlayback() }
        .alert(L("Remove Word?"), isPresented: $showDeleteConfirmation) {
            Button(L("Remove"), role: .destructive) {
                stopPlayback()
                onDelete()
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("\"%@\" will be removed from Seagull Steven's queue and all its learning progress will be lost.", title))
        }
    }

    private func stopPlayback() {
        player.stop()
        if usingTTS { TTSService.shared.stop() }
    }
}
