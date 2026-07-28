import SwiftUI

struct MessageBubbleView: View {
    let message: LocalChatMessage
    let onReplyInThread: () -> Void
    let onPlayFromHere: () -> Void
    let onParrot: () -> Void
    var onAnnotate: (() -> Void)? = nil
    /// Author-specified substrings of this message's text to render in the
    /// accent color — the Spanish phrase(s) being taught plus the general
    /// topic phrase — so the key vocabulary stands out from the surrounding
    /// narration at a glance.
    var highlightTerms: [String] = []
    /// Non-nil only for Madrid's one auto-triggered post-practice feedback
    /// message — drives the result chips and the distinct background that
    /// set it apart from an ordinary explanation or Q&A bubble.
    var practiceSummary: PracticeResult? = nil
    // Real names instead of generic "Host"/"Guest" labels — this also matters
    // beyond the label itself: if the student types something like "let the
    // driver answer" or "let Madrid answer", the name shown here is the same
    // name the turn classifier and generation prompts reason about, so what's
    // on screen matches what the student can actually refer to.
    var guestDisplayName: String = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser { Spacer(minLength: 56) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
                if isObjectSpeaker {
                    Label(guestDisplayName.isEmpty ? L("Guest") : guestDisplayName, systemImage: "theatermasks.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.purple.opacity(0.85))
                        .padding(.leading, 4)
                } else if isHostSpeaker {
                    Label("Madrid", systemImage: "mic.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.yellow.opacity(0.85))
                        .padding(.leading, 4)
                }
                bubbleContent
                    .overlay(alignment: .topTrailing) {
                        if message.isAssistant, let annotate = onAnnotate {
                            annotateButton(action: annotate)
                        }
                    }
                    .onTapGesture(count: 2) {
                        if message.isAssistant {
                            onParrot()
                        }
                    }
                    .contextMenu {
                        if message.isAssistant {
                            Button {
                                onReplyInThread()
                            } label: {
                                Label(L("Reply in Thread"), systemImage: "bubble.left.and.bubble.right")
                            }
                        }
                    }
                if message.isAssistant {
                    footer
                }
            }

            if message.isAssistant { Spacer(minLength: 56) }
        }
    }

    // MARK: - Bubble

    @ViewBuilder
    private var bubbleContent: some View {
        let images = message.resolvedImagePaths.compactMap { UIImage(contentsOfFile: $0) }
        VStack(alignment: .leading, spacing: 8) {
            if !images.isEmpty {
                imageThumbnails(images)
            }
            if let summary = practiceSummary {
                practiceSummaryHeader(summary)
            }
            if let text = message.textContent, !text.isEmpty {
                Text(highlightedText(text))
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundColor(message.isUser ? .black : AppColors.textPrimary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, images.isEmpty ? 16 : 10)
        .padding(.vertical, images.isEmpty ? 12 : 10)
        .background(bubbleBackground)
        .clipShape(BubbleShape(isUser: message.isUser))
        .overlay(
            BubbleShape(isUser: message.isUser)
                .stroke(bubbleBorder, lineWidth: 1)
        )
    }

    /// Case/accent-insensitive-free (exact substring) highlighting of the
    /// author-specified key terms — longest terms first so e.g. "hasta
    /// luego" is matched whole rather than leaving a shorter substring
    /// double-matched inside it.
    private func highlightedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !highlightTerms.isEmpty else { return attributed }
        for term in highlightTerms.sorted(by: { $0.count > $1.count }) where !term.isEmpty {
            var searchStart = attributed.startIndex
            while let range = attributed[searchStart...].range(of: term, options: .caseInsensitive) {
                attributed[range].foregroundColor = AppColors.accent
                attributed[range].font = .system(size: 20, weight: .semibold, design: .rounded)
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    /// Quick at-a-glance summary: one small chip per question, green/red for
    /// correct/incorrect, before the reader gets to the paragraph explaining
    /// why — this is what actually marks a bubble as "practice results" from
    /// across the room, not just its wording.
    private func practiceSummaryHeader(_ summary: PracticeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("PRACTICE RESULTS"))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(GameColors.gold)
                .tracking(0.5)
            HStack(spacing: 6) {
                ForEach(Array(summary.answers.enumerated()), id: \.offset) { _, answer in
                    Image(systemName: answer.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(answer.wasCorrect ? GameColors.verde : GameColors.rojo)
                }
            }
        }
    }

    private func imageThumbnails(_ images: [UIImage]) -> some View {
        let columns = min(images.count, 2)
        let size: CGFloat = columns == 1 ? 220 : 108
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(size), spacing: 4), count: columns),
            spacing: 4
        ) {
            ForEach(images.indices, id: \.self) { i in
                Image(uiImage: images[i])
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .clipped()
            }
        }
    }

    // MARK: - Footer

    private let actionButtonSize: CGFloat = 40

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if TTSService.shared.playingMessageId == message.id {
                audioProgressBar
            }
            HStack(spacing: 0) {
                parrotButton
                Spacer()
                replyButton
                Spacer()
                speakerButton
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var audioProgressBar: some View {
        let tts = TTSService.shared
        let isActive = tts.playingMessageId == message.id
        if isActive && tts.duration > 0 {
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { tts.currentTime },
                        set: { tts.seek(to: $0) }
                    ),
                    in: 0...max(tts.duration, 1)
                )
                .tint(.yellow)
                .frame(maxWidth: .infinity)

                HStack {
                    Text(formatTime(tts.currentTime))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                    Spacer()
                    Text(formatTime(tts.duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private var speakerButton: some View {
        if let _ = message.textContent {
            let tts = TTSService.shared
            let isPlaying = tts.playingMessageId == message.id
            let isLoadingThis = tts.loadingMessageId == message.id
            let isPausedHere = isPlaying && tts.isPaused

            Button {
                if isPlaying {
                    tts.togglePause()
                } else {
                    onPlayFromHere()
                }
            } label: {
                ZStack {
                    if isLoadingThis {
                        ProgressView()
                            .tint(.yellow)
                            .scaleEffect(0.85)
                    } else if isPlaying {
                        Image(systemName: isPausedHere ? "play.fill" : "pause.fill")
                            .font(.system(size: 18, design: .rounded))
                            .foregroundColor(.yellow)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, design: .rounded))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .foregroundColor(isPlaying || isLoadingThis ? .yellow : AppColors.textTertiary)
                .frame(width: actionButtonSize, height: actionButtonSize)
                .background(isPlaying ? Color.yellow.opacity(0.12) : Color.white.opacity(0.07))
                .clipShape(Circle())
                .overlay(Circle().stroke(isPlaying ? Color.yellow.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1))
            }
            .disabled(isLoadingThis)
        }
    }

    @ViewBuilder
    private var parrotButton: some View {
        if message.isAssistant, let text = message.textContent, !text.isEmpty {
            Button(action: onParrot) {
                Image("icon_brain")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }

    private func annotateButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image("icon_eye")
                .resizable()
                .scaledToFill()
                .frame(width: actionButtonSize, height: actionButtonSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .offset(x: 12, y: -12)
    }

    @ViewBuilder
    private var replyButton: some View {
        if message.isAssistant, let text = message.textContent, !text.isEmpty {
            Button(action: onReplyInThread) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if message.threadReplyCount > 0 {
                            replyCountBadge
                        }
                    }
            }
        }
    }

    private var replyCountBadge: some View {
        Text("\(message.threadReplyCount)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .frame(minWidth: 16, minHeight: 16)
            .background(Circle().fill(Color.yellow))
            .offset(x: 4, y: -4)
    }

    private var isObjectSpeaker: Bool {
        message.speakerId == "object"
    }

    private var isHostSpeaker: Bool {
        message.speakerId == "madrid"
    }

    private var bubbleBackground: Color {
        if message.isUser { return .yellow }
        if practiceSummary != nil { return GameColors.gold.opacity(0.14) }
        // Roleplay bubbles sit on top of a busy scene photo (unlike regular
        // chat's flat background), so they need much more opacity than the
        // generic glass-card look to keep text legible.
        if isObjectSpeaker { return Color.purple.opacity(0.55) }
        if isHostSpeaker { return Color.black.opacity(0.55) }
        return AppColors.cardBackground
    }

    private var bubbleBorder: Color {
        if message.isUser { return .yellow.opacity(0.6) }
        if practiceSummary != nil { return GameColors.gold.opacity(0.45) }
        if isObjectSpeaker { return Color.purple.opacity(0.7) }
        if isHostSpeaker { return Color.white.opacity(0.25) }
        return AppColors.cardBorder
    }
}

struct BubbleShape: Shape {
    let isUser: Bool
    let radius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let minRadius: CGFloat = 4
        var path = Path()

        let tl: CGFloat = isUser ? radius : minRadius
        let tr: CGFloat = isUser ? minRadius : radius
        let bl: CGFloat = radius
        let br: CGFloat = radius

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
