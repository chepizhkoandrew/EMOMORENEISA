import SwiftUI
import SwiftData

/// Step 2 of the song flow — styled like the onboarding quiz (same background
/// family, the smiling dog, a mic orb) but focused on collecting the song's
/// content: words from the memorize queue, and typed/pasted/spoken lyrics.
struct MusicLyricsView: View {
    @Bindable var model: MusicFlowModel

    @Query(filter: #Predicate<MemoryCard> { !$0.isArchived }, sort: \MemoryCard.createdAt, order: .reverse)
    private var memoryCards: [MemoryCard]

    @FocusState private var lyricsFocused: Bool
    @State private var showKaraoke = false
    /// Preloading starts the moment the song is `.ready` (see `onChange`
    /// below), not when the user taps Play — by then most/all pictures are
    /// already downloaded and karaoke starts smoothly from the first second.
    @State private var sceneImages = KaraokeSceneImages()

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
        .fullScreenCover(isPresented: $showKaraoke) {
            if let song = model.song {
                MusicKaraokeView(song: song, memoryCards: Array(memoryCards), sceneImages: sceneImages)
            }
        }
        .onChange(of: model.phase) { _, newPhase in
            if case .ready = newPhase, let song = model.song {
                sceneImages.load(scenes: song.scenes, cards: memoryCards)
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
                    if !model.selectedGenres.isEmpty {
                        Text("\(model.selectedGenres.joined(separator: ", ")) · \(L(model.length.titleKey))")
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

                        // Fixed to ~6 lines and scrollable — a big queue would
                        // otherwise push the lyrics box far down the screen.
                        ScrollView(showsIndicators: true) {
                            ChipFlowLayout(spacing: 8) {
                                ForEach(memoryCards, id: \.id) { card in
                                    wordChip(card)
                                }
                            }
                        }
                        .frame(height: 230)
                    }
                }

                lyricsBox

                Toggle(isOn: $model.useAsExactLyrics) {
                    Text(L("These are the exact lyrics — sing them as written"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                .tint(.yellow)

                if case .failed(let message) = model.phase {
                    failedCard(message)
                }

                generateButton
                    .padding(.top, 4)
                    .padding(.bottom, 44)
            }
            .padding(.horizontal, HomeLayout.hPadding)
            // Tapping any empty space (not a chip, not the text box itself —
            // those consume their own tap first) also dismisses the keyboard,
            // as a second path alongside the keyboard toolbar's Done button.
            .contentShape(Rectangle())
            .onTapGesture { lyricsFocused = false }
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

    // MARK: - Lyrics box (text field + inline mic — self-explanatory, no header)

    private var lyricsBox: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.lyricsText)
                    .focused($lyricsFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .frame(minHeight: 130)
                    .padding(10)
                    .padding(.trailing, 46) // room for the mic button
                    .padding(.bottom, 20)
                    // TextEditor has no Return-to-submit and, unlike a plain
                    // background tap, this is reachable even when the
                    // keyboard is covering everything below it (as it does
                    // on a 30s-song-sized screen) — without this there was no
                    // way at all to get the keyboard back down.
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(L("Done")) { lyricsFocused = false }
                                .fontWeight(.bold)
                        }
                    }

                if model.lyricsText.isEmpty {
                    Text(L("e.g. a happy song about ordering food at the beach…"))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }

                if model.recorder.isRecording {
                    Text(L("Listening… tap to stop"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }

            micButton
                .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Combined into the lyrics box itself (trailing edge) rather than a
    /// separate row with instructional copy — the placeholder text already
    /// explains what to type, and a mic icon is self-explanatory.
    private var micButton: some View {
        Button {
            Task { await model.toggleMic() }
        } label: {
            ZStack {
                Circle()
                    .fill(model.recorder.isRecording ? Color.red : Color.yellow)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                if model.recorder.isRecording {
                    EdgeEqualizerRing(level: model.recorder.audioLevel,
                                      color: .white.opacity(0.9),
                                      diameter: 40)
                }
                if model.isTranscribing {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: model.recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isTranscribing)
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
            .foregroundColor(model.canGenerate ? .black : .white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(model.canGenerate ? Color.yellow : Color.white.opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canGenerate)
    }

    // MARK: - Working state (real progress bar + rotating fun stages)

    /// (elapsed fraction of the estimate, what to say) — up to 6 stages. Text
    /// is deliberately playful; the fraction just needs to feel roughly right,
    /// not be exact, since the bar itself is what the user is watching.
    private static let workingStages: [(threshold: Double, text: String)] = [
        (0.00, "Warming up the studio…"),
        (0.14, "Tuning the instruments…"),
        (0.30, "Writing your lyrics…"),
        (0.52, "Finding the melody…"),
        (0.74, "Recording the vocals…"),
        (0.90, "Mixing the final track…")
    ]

    /// Purely elapsed-time-based — smooth and monotonic — and deliberately
    /// NEVER touched by the server's reported stage. It used to jump to a
    /// hard floor (0.55) the moment the server reported "generating", which
    /// looked fine when composeLyrics took real time first, but once exact
    /// lyrics became the permanent default, the server skips straight to
    /// "generating" within a few seconds of any job starting — so the number
    /// would jump from ~1% to 55% almost instantly and then sit there doing
    /// nothing until elapsed time genuinely caught back up. A progress
    /// number the user is staring at has to move evenly; the real stage is
    /// still useful, it just belongs on the caption below, not the number.
    private func workingFraction(now: Date) -> Double {
        guard let started = model.workingStartedAt else { return 0 }
        let elapsed = now.timeIntervalSince(started)
        return min(0.95, max(0, elapsed / Double(max(1, model.etaSeconds))))
    }

    /// The caption can jump ahead of the time-based fraction when the server
    /// confirms we're genuinely past a milestone (e.g. straight to
    /// "generating" because exact lyrics skipped the writing stage) — an
    /// instant text swap reads as "oh, further along than the bar suggests",
    /// not as broken the way a stalled progress *number* would.
    private func workingStageText(fraction: Double) -> String {
        let timeIndex = Self.workingStages.lastIndex { fraction >= $0.threshold } ?? 0
        var floorIndex = 0
        if case .working(let stage) = model.phase {
            if stage == "writing_lyrics" { floorIndex = 2 } // "Writing your lyrics…"
            if stage == "generating" { floorIndex = 4 }     // "Recording the vocals…"
        }
        let index = min(max(timeIndex, floorIndex), Self.workingStages.count - 1)
        return Self.workingStages[index].text
    }

    private var workingCard: some View {
        TimelineView(.animation) { context in
            let fraction = workingFraction(now: context.date)
            VStack(spacing: 18) {
                Text(L(workingStageText(fraction: fraction)))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: workingStageText(fraction: fraction))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.yellow)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 8)

                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .padding(.horizontal, 32)
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

                    // One control: Play means karaoke — pictures + synced
                    // lyrics — there's no separate silent-audio preview anymore.
                    Button {
                        showKaraoke = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 96, height: 96)
                                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                            Image(systemName: "play.fill")
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)

                    if !song.lyrics.isEmpty {
                        LyricsHighlight.highlightedLyrics(
                            song.lyrics,
                            targets: song.scenes.map(\.word),
                            baseColor: .white.opacity(0.85),
                            highlightColor: LyricsHighlight.highlightColor
                        )
                        .font(.system(size: 15, weight: .medium, design: .rounded))
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
