import SwiftUI
import SwiftData

/// Step 2 of the song flow — styled like the onboarding quiz (same background
/// family, the smiling dog, a mic orb) but focused on collecting the song's
/// content: words from the memorize queue, typed/pasted lyrics or a free-form
/// description, or a spoken brief via the same STT pipeline the quiz uses.
struct MusicLyricsView: View {
    @Bindable var model: MusicFlowModel

    @Query(filter: #Predicate<MemoryCard> { !$0.isArchived }, sort: \MemoryCard.createdAt, order: .reverse)
    private var memoryCards: [MemoryCard]

    @FocusState private var lyricsFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                dogCharacter(in: geo.size)

                switch model.phase {
                case .ready:
                    resultCard
                case .submitting, .working:
                    workingCard
                default:
                    editor
                }
            }
        }
    }

    // MARK: - Editor

    private var editor: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("What should it sing?"))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    if let genre = model.selectedGenre {
                        Text("\(genre) · \(L(model.length.titleKey))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.top, 64)

                if !memoryCards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Words from your memory queue"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))

                        ChipFlowLayout(spacing: 8) {
                            ForEach(memoryCards.prefix(24), id: \.id) { card in
                                wordChip(card)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Describe the song, or paste your lyrics"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.lyricsText)
                            .focused($lyricsFocused)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minHeight: 120)
                            .padding(10)

                        if model.lyricsText.isEmpty {
                            Text(L("e.g. a happy song about ordering food at the beach…"))
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.35))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black.opacity(0.42))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                    Toggle(isOn: $model.useAsExactLyrics) {
                        Text(L("These are the exact lyrics — sing them as written"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .tint(.yellow)
                }

                speakRow

                if case .failed(let message) = model.phase {
                    failedCard(message)
                }

                generateButton
                    .padding(.top, 4)
                    .padding(.bottom, 44)
            }
            .padding(.horizontal, HomeLayout.hPadding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func wordChip(_ card: MemoryCard) -> some View {
        let isSelected = model.selectedWords.contains(card.content)
        return Button {
            model.toggleWord(card.content)
        } label: {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
                Text(card.content)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.yellow : Color.white.opacity(0.09))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speak row (same pipeline as the quiz mic)

    private var speakRow: some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.toggleMic() }
            } label: {
                ZStack {
                    Circle()
                        .fill(model.recorder.isRecording ? Color.red : Color.yellow)
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    if model.recorder.isRecording {
                        EdgeEqualizerRing(level: model.recorder.audioLevel,
                                          color: .white.opacity(0.9),
                                          diameter: 64)
                    }
                    if model.isTranscribing {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: model.recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isTranscribing)

            Text(model.recorder.isRecording
                 ? L("Listening… tap to stop")
                 : L("Or tap and say what the song should be about"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Generate

    private var generateButton: some View {
        Button {
            lyricsFocused = false
            model.generate()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .heavy))
                Text(L("Create my song"))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                HStack(spacing: 4) {
                    Image("dream_hotdog")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("\(model.length.treatCost)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.18))
                .clipShape(Capsule())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(model.canGenerate ? Color.yellow : Color.white.opacity(0.18))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canGenerate)
    }

    // MARK: - Working / result / failure states

    private var workingCard: some View {
        VStack(spacing: 18) {
            PulsingEqualizerView(color: .yellow, barCount: 9,
                                 maxHeight: 52, barWidth: 4.5, spacing: 4.5)
                .frame(height: 60)

            Text(workingText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(L("First song of the day can take a couple of minutes — the studio is warming up."))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .padding(.horizontal, 32)
    }

    private var workingText: String {
        switch model.phase {
        case .working(let stage) where stage == "writing_lyrics":
            return L("Writing your lyrics…")
        case .working(let stage) where stage == "generating":
            return L("Recording your song…")
        default:
            return L("Sending to the studio…")
        }
    }

    private var resultCard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if let song = model.song {
                    Text(song.title.isEmpty ? L("Your song is ready!") : song.title)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 80)

                    Text("\(song.genre) · \(song.durationSec)s")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)

                    Button {
                        model.togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 96, height: 96)
                                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)

                    if !song.lyrics.isEmpty {
                        Text(song.lyrics)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(18)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.42)))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    }

                    Button {
                        model.startOver()
                    } label: {
                        Text(L("Create another"))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Capsule().stroke(Color.yellow.opacity(0.5), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 44)
                }
            }
            .padding(.horizontal, HomeLayout.hPadding)
        }
    }

    private func failedCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(L("That take didn't work out — your treats were refunded."))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(L("Tweak something and try again."))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Dog (same character/placement family as the quiz)

    @ViewBuilder
    private func dogCharacter(in size: CGSize) -> some View {
        let dogSize = min(size.width * 0.5, 260)
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image("onboard_dog")
                    .resizable()
                    .scaledToFit()
                    .frame(width: dogSize)
                    .opacity(0.5)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .offset(x: dogSize * 0.10, y: dogSize * 0.04)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}
