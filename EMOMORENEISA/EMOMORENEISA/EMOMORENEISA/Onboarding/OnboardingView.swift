import SwiftUI
import AVFoundation

// Voice quiz screen (Phase B). The visual language matches the intro slides:
// GameBackground + DreamParticlesView + Professor Madrid as a character in
// the bottom-right corner. There is exactly ONE mic control on screen and
// it only appears once the question has finished playing.

struct OnboardingView: View {
    @Bindable var store: OnboardingStore
    @Bindable var coordinator: OnboardingCoordinator
    var onCompleted: () -> Void

    @State private var micPermissionDenied: Bool = false
    @State private var displayedText: String = ""
    @State private var typewriterTask: Task<Void, Never>? = nil
    @State private var thinkingProgress: Double = 0
    @State private var thinkingProgressTask: Task<Void, Never>? = nil
    @State private var arrowScale: CGFloat = 1.0
    @State private var arrowSpinCount: Int = 0

    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                dogCharacter(in: geo.size)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    backArrow
                    Spacer()
                    progressDots
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer(minLength: 12)

                if micPermissionDenied {
                    micDeniedCard
                } else if case .failed = coordinator.phase {
                    failedCard
                        .padding(.horizontal, 22)
                        .frame(height: 240, alignment: .center)
                } else if case .thinking = coordinator.phase {
                    thinkingCard
                        .padding(.horizontal, 22)
                        .frame(height: 240, alignment: .center)
                } else {
                    questionCard
                        .padding(.horizontal, 22)
                        .frame(height: 240, alignment: .center)
                }

                Spacer(minLength: 20)

                waveformOrb

                reviewTranscriptCard
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .frame(height: reviewSlotHeight, alignment: .top)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)

            if case .done = coordinator.phase {
                doneOverlay
            }
        }
        .onAppear { requestMicAndStart() }
        .onChange(of: coordinator.phase) { _, new in
            handlePhaseChange(new)
        }
    }

    private func handlePhaseChange(_ phase: OnboardingCoordinator.Phase) {
        switch phase {
        case .playingQuestion:
            stopThinkingProgress()
            startTypewriter(for: store.currentQuestionText)
        case .awaitingAnswer, .reviewingAnswer, .closing:
            stopThinkingProgress()
            typewriterTask?.cancel()
            displayedText = store.currentQuestionText
        case .thinking:
            typewriterTask?.cancel()
            startThinkingProgress()
        case .transcribing:
            typewriterTask?.cancel()
        case .done:
            stopThinkingProgress()
            typewriterTask?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { onCompleted() }
        case .failed:
            stopThinkingProgress()
            typewriterTask?.cancel()
        default:
            break
        }
    }

    private func startThinkingProgress() {
        thinkingProgressTask?.cancel()
        thinkingProgress = 0
        thinkingProgressTask = Task {
            let steps = 160
            let targetFraction = 0.82
            for i in 1...steps {
                guard !Task.isCancelled else { return }
                let eased = 1 - pow(1 - Double(i) / Double(steps), 2.2)
                withAnimation(.linear(duration: 0.22)) {
                    thinkingProgress = eased * targetFraction
                }
                do {
                    try await Task.sleep(nanoseconds: 220_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func stopThinkingProgress() {
        thinkingProgressTask?.cancel()
        thinkingProgressTask = nil
        withAnimation(.easeOut(duration: 0.3)) {
            thinkingProgress = 0
        }
    }

    private func typewriterDelay(after char: Character) -> UInt64 {
        if ".!?".contains(char) { return 420_000_000 }
        if ",;:".contains(char) { return 180_000_000 }
        return 28_000_000
    }

    private func startTypewriter(for text: String) {
        typewriterTask?.cancel()
        displayedText = ""
        typewriterTask = Task {
            var built = ""
            for char in text {
                guard !Task.isCancelled else { return }
                built.append(char)
                displayedText = built
                do {
                    try await Task.sleep(nanoseconds: typewriterDelay(after: char))
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - Thinking card

    private var thinkingCard: some View {
        VStack(spacing: 20) {
            Text(coordinator.thinkingLabel.isEmpty
                 ? (store.quizLanguage == .uk ? "Хвилинку…" : "One sec…")
                 : coordinator.thinkingLabel)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(thinkingProgress), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .transition(.opacity)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            GameBackground()
            DreamParticlesView()
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }

    // MARK: - Dog character

    @ViewBuilder
    private func dogCharacter(in size: CGSize) -> some View {
        let dogSize = min(size.width * 0.62, 320)
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image("onboard_dog")
                    .resizable()
                    .scaledToFit()
                    .frame(width: dogSize)
                    .opacity(0.95)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .offset(x: dogSize * 0.06, y: dogSize * 0.02)
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        let count = OnboardingQuestionBank.progressCount
        let currentIndex = store.currentSlot.indexForProgress ?? 0
        return HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(dotColor(index: i, current: currentIndex))
                    .frame(width: i == currentIndex ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.35), value: currentIndex)
            }
        }
    }

    private func dotColor(index: Int, current: Int) -> Color {
        if index < current { return .yellow }
        if index == current { return .yellow }
        return .white.opacity(0.3)
    }

    // MARK: - Question card (visible while playing AND while awaiting)

    @ViewBuilder
    private var questionCard: some View {
        let text = subtitleText()
        if !text.isEmpty && subtitleVisible {
            Text(text)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(0.42))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .transition(.opacity)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var subtitleVisible: Bool {
        // Show the question the whole time — while the tutor is still speaking
        // (so the user can read along), while we're waiting for an answer, and
        // while the user is reviewing what they just said. Hide it only during
        // the transient thinking / transcribing beats where a placeholder text
        // is shown instead.
        switch coordinator.phase {
        case .idle, .failed: return false
        default: return true
        }
    }

    private func subtitleText() -> String {
        switch coordinator.phase {
        case .thinking:
            return store.quizLanguage == .uk ? "Хвилинку…" : "One sec…"
        case .transcribing:
            return store.quizLanguage == .uk ? "Слухаю тебе…" : "Got that…"
        case .playingQuestion:
            return displayedText
        default:
            return store.currentQuestionText
        }
    }

    // MARK: - Back arrow (top-left)

    @ViewBuilder
    private var backArrow: some View {
        if coordinator.canGoBack && backArrowVisible {
            Button {
                Task { await coordinator.goBackOneSlot() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var backArrowVisible: Bool {
        // Never let the user jump out of a live analyst / synthesis / closing
        // beat — only allow back-navigation from user-facing phases.
        switch coordinator.phase {
        case .awaitingAnswer, .reviewingAnswer, .playingQuestion: return true
        default: return false
        }
    }

    // MARK: - Unified action orb
    //
    // ONE circle at a fixed position and size. The content inside swaps
    // between an animated equalizer (while the tutor is speaking or the user
    // is recording) and a mic icon (while awaiting or reviewing an answer).
    // The circle itself is always the same size / shape / position so the
    // user's eye never has to jump.

    // Slightly smaller than the previous 150 so the orb doesn't crowd the
    // dog character and doesn't jump between speaking / recording states —
    // its frame is now constant across every phase.
    private let orbSize: CGFloat = 128
    // Fixed height reserved for the review-transcript card slot. The card
    // itself only renders in `.reviewingAnswer`, but the slot is always
    // this tall so the orb above it never shifts.
    private let reviewSlotHeight: CGFloat = 220

    @ViewBuilder
    private var waveformOrb: some View {
        VStack(spacing: 10) {
            Button {
                Task { await coordinator.toggleMic() }
            } label: {
                ZStack {
                    Circle()
                        .fill(orbFill)
                        .frame(width: orbSize, height: orbSize)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .frame(width: orbSize, height: orbSize)
                    if isRecording {
                        EdgeEqualizerRing(level: coordinator.recorder.audioLevel,
                                          color: .white.opacity(0.9),
                                          diameter: orbSize)
                    }
                    orbContent
                }
            }
            .buttonStyle(.plain)
            .disabled(!orbTappable)
            .frame(width: orbSize, height: orbSize)

            countdownBadge
                .frame(height: 22)
        }
    }

    @ViewBuilder
    private var countdownBadge: some View {
        if isRecording && coordinator.recordingSecondsRemaining > 0 {
            let s = coordinator.recordingSecondsRemaining
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("\(s)s")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundColor(s <= 5 ? .red : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private var orbFill: Color {
        switch coordinator.phase {
        case .recording: return Color.red
        case .transcribing, .thinking, .closing: return Color.yellow.opacity(0.55)
        default: return Color.yellow
        }
    }

    private var orbTappable: Bool {
        switch coordinator.phase {
        // `.playingQuestion` is tappable so the user can interrupt the
        // question audio and jump straight into recording their answer.
        case .awaitingAnswer, .reviewingAnswer, .recording, .playingQuestion:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var orbContent: some View {
        switch coordinator.phase {
        case .playingQuestion, .closing:
            PulsingEqualizerView(color: .black, barCount: 9,
                                 maxHeight: 52, barWidth: 4.5, spacing: 4.5)
        case .recording:
            Image(systemName: "stop.fill")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        case .transcribing, .thinking:
            ProgressView().tint(.black).scaleEffect(1.3)
        default:
            Image(systemName: "mic.fill")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.black)
        }
    }

    private var coordinatorIsPlaying: Bool {
        if case .playingQuestion = coordinator.phase { return true }
        if case .closing = coordinator.phase { return true }
        return false
    }

    private var isRecording: Bool {
        if case .recording = coordinator.phase { return true }
        return false
    }

    // MARK: - Review transcript card + forward arrow
    //
    // Shown after the user stops recording (`.reviewingAnswer`). The transcript
    // is visible so the user can confirm what was captured; tapping the
    // forward arrow advances to the next question, tapping the mic orb above
    // re-records. Back navigation lives in the top-left arrow.

    /// One-shot "notice me" nudge on the forward arrow — pops bigger then
    /// settles back, with a single full spin, so the user notices there's
    /// now a way forward without any added text. Fires fresh every time the
    /// arrow (re)appears, since `reviewTranscriptCard`'s `if` branch tears
    /// the button down between questions — `.onAppear` naturally retriggers
    /// it each time. `arrowSpinCount` only ever increments (never resets to
    /// 0), so each hint is a clean forward spin from wherever it last ended
    /// rather than an abrupt snap-back.
    private func playArrowHint() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
            arrowScale = 1.24
            arrowSpinCount += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                arrowScale = 1.0
            }
        }
    }

    @ViewBuilder
    private var reviewTranscriptCard: some View {
        if case .reviewingAnswer = coordinator.phase,
           !coordinator.lastTranscriptPreview.isEmpty {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    TextEditor(text: Binding(
                        get: { coordinator.lastTranscriptPreview },
                        set: { coordinator.updateTranscript($0) }
                    ))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxHeight: 160)
                    .tint(.yellow)
                }
                Button {
                    Task { await coordinator.confirmAndAdvance() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 48, height: 48)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                    }
                    .scaleEffect(arrowScale)
                    .rotationEffect(.degrees(Double(arrowSpinCount) * 360))
                }
                .buttonStyle(.plain)
                .onAppear { playArrowHint() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.42))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Color.clear.frame(height: 0)
        }
    }

    // Kept for backward-compat with any layout that referenced controlRow.
    // Empty because the action orb now owns record + re-record, and the
    // forward arrow lives inside the review transcript card.
    @ViewBuilder
    private var controlRow: some View {
        Color.clear.frame(height: 0)
    }

    // MARK: - Failed card
    //
    // Rendered whenever the coordinator lands in `.failed`. Previously this
    // phase drew NOTHING (no card, orb disabled) — a frozen-looking screen
    // that App Review flagged as "app froze on the tutorial screen". Always
    // give the user a visible way forward.

    private var failedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, design: .rounded))
                .foregroundColor(.orange)
            Text(store.quizLanguage == .uk
                 ? "Щось пішло не так. Спробуймо ще раз."
                 : "Something went wrong. Let's try that again.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button {
                Task { await coordinator.retryAfterFailure() }
            } label: {
                Text(store.quizLanguage == .uk ? "Спробувати ще раз" : "Try again")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.42)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Mic denied card

    private var micDeniedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 36, design: .rounded))
                .foregroundColor(.orange)
            Text(store.quizLanguage == .uk
                 ? "Мікрофон не дозволено. Будь ласка, дозволь його в Налаштуваннях."
                 : "Microphone is not allowed. Please allow it in the Settings.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(store.quizLanguage == .uk ? "Відкрити Налаштування" : "Open Settings")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.42)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 22)
        .frame(height: 240, alignment: .center)
    }

    private func requestMicAndStart() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    micPermissionDenied = false
                    Task { await coordinator.start() }
                } else {
                    micPermissionDenied = true
                }
            }
        }
    }

    // MARK: - Done overlay

    private var doneOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(store.quizLanguage == .uk
                     ? "Класно поспілкувалися!"
                     : "Great to meet you!")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Equalizer bar views used by the action orb

/// Purely time-driven equalizer used while the tutor is speaking. We don't
/// have live playback levels, so we synthesise motion with a summed-sines
/// profile per bar — reads as "audio is playing right now".
struct PulsingEqualizerView: View {
    var color: Color
    var barCount: Int = 9
    var maxHeight: CGFloat = 62
    var barWidth: CGFloat = 5
    var spacing: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = Double(i) * 0.55 + t * 4.2
                    let value = 0.35 + 0.32 * sin(phase) + 0.20 * sin(phase * 1.7 + Double(i))
                    let normalized = max(0.14, min(1.0, value))
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth,
                               height: max(6, maxHeight * CGFloat(normalized)))
                }
            }
            .frame(height: maxHeight)
        }
    }
}

/// Level-driven equalizer used while the user is recording. Reads the live
/// audioLevel from the recorder and modulates a set of bars around it.
struct LiveEqualizerView: View {
    var level: Float
    var color: Color
    var barCount: Int = 9
    var maxHeight: CGFloat = 62
    var barWidth: CGFloat = 5
    var spacing: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let base = Double(max(0.05, min(1.0, level)))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let jitter = 0.35 * sin(t * 8.0 + Double(i) * 0.9)
                    let value = base * (0.65 + jitter)
                    let normalized = max(0.10, min(1.0, value))
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth,
                               height: max(6, maxHeight * CGFloat(normalized)))
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(height: maxHeight)
        }
    }
}

/// Level-driven equalizer arranged as a ring around the orb's edge, used
/// while recording. The center of the orb shows a stop icon instead, so a
/// glance makes it clear that tapping again stops the recording — rather
/// than looking like the user must wait out the full time limit.
struct EdgeEqualizerRing: View {
    var level: Float
    var color: Color
    var diameter: CGFloat
    var barCount: Int = 28
    var barWidth: CGFloat = 2.5
    var minLength: CGFloat = 5
    var maxLength: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let base = Double(max(0.05, min(1.0, level)))
            let radius = diameter / 2 - maxLength / 2 - 3
            ZStack {
                ForEach(0..<barCount, id: \.self) { i in
                    let angle = Double(i) / Double(barCount) * 360.0
                    let jitter = 0.35 * sin(t * 8.0 + Double(i) * 0.9)
                    let value = base * (0.65 + jitter)
                    let normalized = max(0.12, min(1.0, value))
                    let length = minLength + (maxLength - minLength) * CGFloat(normalized)
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: length)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(angle))
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(width: diameter, height: diameter)
        }
    }
}
