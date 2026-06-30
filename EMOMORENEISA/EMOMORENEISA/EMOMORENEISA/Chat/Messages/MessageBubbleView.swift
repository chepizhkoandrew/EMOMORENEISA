import SwiftUI

struct MessageBubbleView: View {
    let message: LocalChatMessage
    let onReplyInThread: () -> Void
    let onPlayFromHere: () -> Void
    let onParrot: () -> Void
    var onAnnotate: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser { Spacer(minLength: 56) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
                bubbleContent
                    .overlay(alignment: .topTrailing) {
                        if message.isAssistant, let annotate = onAnnotate {
                            annotateButton(action: annotate)
                        }
                    }
                    .contextMenu {
                        if message.isAssistant {
                            Button {
                                onReplyInThread()
                            } label: {
                                Label("Reply in Thread", systemImage: "bubble.left.and.bubble.right")
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
            if let text = message.textContent, !text.isEmpty {
                Text(text)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundColor(message.isUser ? .black : AppColors.textPrimary)
                    .lineSpacing(5)
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
                speakerButton
                if message.threadReplyCount > 0 {
                    replyBadge.padding(.leading, 16)
                }
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
                            .font(.system(size: 18))
                            .foregroundColor(.yellow)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image("icon_beak")
                            .resizable()
                            .scaledToFill()
                            .frame(width: actionButtonSize, height: actionButtonSize)
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
                    .scaledToFill()
                    .frame(width: actionButtonSize, height: actionButtonSize)
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
    private var replyBadge: some View {
        if message.threadReplyCount > 0 {
            Button(action: onReplyInThread) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 19))
                    Text("\(message.threadReplyCount) \(message.threadReplyCount == 1 ? "reply" : "replies")")
                        .font(.system(size: 20, weight: .medium))
                }
                .foregroundColor(.yellow.opacity(0.8))
            }
        }
    }

    private var bubbleBackground: Color {
        message.isUser ? .yellow : AppColors.cardBackground
    }

    private var bubbleBorder: Color {
        message.isUser ? .yellow.opacity(0.6) : AppColors.cardBorder
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
