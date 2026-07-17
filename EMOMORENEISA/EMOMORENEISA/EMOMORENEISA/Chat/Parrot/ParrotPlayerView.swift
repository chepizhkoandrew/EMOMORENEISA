import SwiftUI
import SwiftData

struct ParrotPlayerView: View {
    let phrase: ParrotPhrase
    let initialLoops: Int
    let messageText: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var service = ParrotService()
    @State private var player = LoopingParrotPlayer()
    @State private var loops: Int
    @State private var memoryToast: Bool = false
    @State private var showCelebration: Bool = false
    @State private var celebrationBounce: Bool = false

    init(phrase: ParrotPhrase, initialLoops: Int, messageText: String? = nil) {
        self.phrase = phrase
        self.initialLoops = initialLoops
        self.messageText = messageText
        _loops = State(initialValue: initialLoops)
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                Spacer()
                mainContent
                Spacer()
                if case .ready = service.state {
                    playerControls
                }
                Spacer(minLength: 28)
            }

            if memoryToast {
                memoryToastBanner
            }

            if showCelebration {
                celebrationOverlay
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .onChange(of: player.isDone) { _, done in
            guard done else { return }
            // Loro Memorize creation gate (spec §1.3): a completed loop run sends
            // the phrase to Loro's memory. Idempotent per sourceParrotId, so a
            // manual replay re-completion never creates a second card.
            let memoryService = MemoryCardService(context: modelContext)
            if memoryService.createCard(from: phrase, loops: player.totalLoops) != nil {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    memoryToast = true
                }
            }

            withAnimation(.easeIn(duration: 0.25)) {
                showCelebration = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                player.stop()
                dismiss()
            }
        }
        .task {
            if phrase.hasAudio {
                await MainActor.run { service.state = .ready }
                player.start(phrase: phrase, loops: loops)
                await service.ensureIllustration(for: phrase)
            } else {
                // Stream: start looping playback the moment segment 1 lands; the
                // player buffers on later segments while they are still arriving.
                await service.generateStreaming(phrase: phrase, level: "Beginner") {
                    player.startStreaming(phrase: phrase, loops: loops, expectedSegments: 7)
                }
                if case .ready = service.state {
                    try? modelContext.save()
                }
            }
        }
        .onDisappear {
            player.stop()
        }
    }

    private var header: some View {
        HStack {
            BackButton {
                player.stop()
                dismiss()
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch service.state {
        case .idle:
            generatingView(progress: 0, label: L("Preparing…"))

        case .generating(let progress, let label):
            generatingView(progress: progress, label: label)

        case .failed(let msg):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44, design: .rounded))
                    .foregroundColor(.orange)
                Text(L("Generation failed"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                Text(msg)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(L("Try Again")) {
                    Task { await service.generate(phrase: phrase, level: "Beginner") }
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

        case .ready:
            playerInfo
        }
    }

    private func generatingView(progress: Double, label: String) -> some View {
        VStack(spacing: 28) {
            LoroImage(asset: .idle, size: 120)
                .scaleEffect(1 + 0.06 * sin(progress * .pi * 6))
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: progress)

            Text(L("Seagull Steven is warming up…"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)

            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.10))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.yellow)
                            .frame(width: geo.size.width * progress)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 32)

                Text(label)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 24)
    }

    private var playerInfo: some View {
        VStack(spacing: 20) {
            LoroIllustrationView(url: phrase.illustrationURL, fallback: .teaching, size: 120)
                .shadow(color: Color.yellow.opacity(0.4), radius: 20)

            VStack(spacing: 8) {
                Text(phrase.spanishPhrase)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                if !phrase.englishTranslation.isEmpty {
                    Text(phrase.englishTranslation)
                        .font(.system(size: 18, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            if !player.isDone {
                VStack(spacing: 6) {
                    Text(L("Loop %d of %d", min(player.currentLoop + 1, player.totalLoops), player.totalLoops))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.yellow)

                    HStack(spacing: 4) {
                        ForEach(0..<player.totalLoops, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i < player.currentLoop ? Color.yellow : Color.white.opacity(0.2))
                                .frame(height: 6)
                                .animation(.easeInOut(duration: 0.3), value: player.currentLoop)
                        }
                    }
                    .padding(.horizontal, 32)
                }
            } else {
                Text(L("Done!"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
            }

            segmentLabel

            if let text = messageText, !text.isEmpty {
                originalMessageView(text: text)
                    .padding(.horizontal, 20)
            }
        }
    }

    private func originalMessageView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("From message"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textTertiary)

            let tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let selectedSet = Set(phrase.selectedWords.map {
                $0.trimmingCharacters(in: .punctuationCharacters).lowercased()
            })

            FlowLayout(hSpacing: 5, vSpacing: 5) {
                ForEach(tokens.indices, id: \.self) { i in
                    let token = tokens[i]
                    let clean = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
                    let isHighlighted = selectedSet.contains(clean)

                    Text(token)
                        .font(.system(size: 14, weight: isHighlighted ? .bold : .regular, design: .rounded))
                        .foregroundColor(isHighlighted ? .black : AppColors.textSecondary.opacity(0.7))
                        .padding(.horizontal, isHighlighted ? 7 : 3)
                        .padding(.vertical, isHighlighted ? 3 : 1)
                        .background(isHighlighted ? Color.yellow : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
    }

    private var memoryToastBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Text("🧠")
                    .font(.system(size: 22, design: .rounded))
                Text(L("This phrase went to Loro's memory"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.yellow)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.yellow.opacity(0.4), radius: 14, y: 4)
            .padding(.bottom, 110)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    private var celebrationOverlay: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                LoroImage(asset: .excited, size: 160)
                    .scaleEffect(celebrationBounce ? 1.09 : 0.94)
                    .animation(
                        .easeInOut(duration: 0.42).repeatForever(autoreverses: true),
                        value: celebrationBounce
                    )
                    .shadow(color: Color.yellow.opacity(0.35), radius: 30)
                    .onAppear { celebrationBounce = true }

                VStack(spacing: 10) {
                    Text("¡Bien hecho!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                        .shadow(color: Color.yellow.opacity(0.55), radius: 18)

                    Text(L("Round complete"))
                        .font(.system(size: 17, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var segmentLabel: some View {
        let labels = [
            L("Spanish phrase"),
            L("English translation"),
            L("Spanish × 1"),
            L("Spanish × 2"),
            L("Spanish × 3"),
            L("Sentence 1"),
            L("Sentence 2")
        ]
        let idx = player.currentSegment
        let label = idx < labels.count ? labels[idx] : ""
        return Text(label)
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(AppColors.textTertiary)
            .animation(.easeInOut, value: player.currentSegment)
    }

    private var playerControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Button {
                    player.skipToPreviousSegment()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(AppColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.cardBorder, lineWidth: 1))
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: 72, height: 72)
                        .background(Color.yellow)
                        .clipShape(Circle())
                        .shadow(color: Color.yellow.opacity(0.4), radius: 12)
                }

                Button {
                    player.skipToNextSegment()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(AppColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.cardBorder, lineWidth: 1))
                }

                Button {
                    player.stop()
                    player.start(phrase: phrase, loops: loops)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 52, height: 52)
                        .background(AppColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.cardBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)

            HStack {
                Text(L("Loops:"))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                HStack(spacing: 0) {
                    ForEach([1, 2, 4, 6, 8, 10, 20], id: \.self) { n in
                        Button {
                            loops = n
                        } label: {
                            Text("\(n)×")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(loops == n ? .black : AppColors.textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(loops == n ? Color.yellow : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }
}
