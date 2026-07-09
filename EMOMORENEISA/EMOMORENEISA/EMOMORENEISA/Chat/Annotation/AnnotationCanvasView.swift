import SwiftUI
import SwiftData
import AVFoundation

private let annotationSynth = AVSpeechSynthesizer()

private let annotationPalette: [Color] = [
    Color(red: 0.22, green: 0.90, blue: 0.40),
    Color(red: 1.00, green: 0.28, blue: 0.28),
    Color(red: 0.25, green: 0.60, blue: 1.00),
    Color(red: 1.00, green: 0.85, blue: 0.10),
    Color(red: 1.00, green: 0.55, blue: 0.10),
    Color(red: 0.75, green: 0.28, blue: 1.00),
    Color(red: 0.10, green: 0.90, blue: 0.90),
    Color(red: 1.00, green: 0.35, blue: 0.75)
]

private enum VoiceState { case idle, recording, transcribing, generating, speaking }

struct AnnotationCanvasView: View {
    let assistantMessage: LocalChatMessage
    let userMessage: LocalChatMessage
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthState.self) private var authState

    @Query private var sessionMessages: [LocalChatMessage]

    @State private var service = AnnotationService()
    @State private var activeLabel: String? = nil
    @State private var pulsing: Bool = false

    @State private var tapCounts: [String: Int] = [:]
    @State private var tapTimers: [String: Task<Void, Never>] = [:]
    @State private var explodingLabel: String? = nil
    @State private var addedToMemory: Set<String> = []
    @State private var memoryToast: String? = nil
    @State private var memoryAddedCount = 0
    @State private var showMemorizeHub = false

    @State private var zoomBase: CGFloat = 1.0
    @State private var zoomDelta: CGFloat = 1.0
    @State private var panBase: CGSize = .zero
    @State private var panDelta: CGSize = .zero

    @State private var voiceRecorder = AudioRecorder()
    @State private var voiceState: VoiceState = .idle
    @State private var lastVoiceReply: String? = nil
    private let openAI = ChatOpenAIService()

    private var firstImage: UIImage? {
        userMessage.resolvedImagePaths.first.flatMap { UIImage(contentsOfFile: $0) }
    }

    private var currentZoom: CGFloat { min(5.0, max(1.0, zoomBase * zoomDelta)) }
    private var currentPan: CGSize {
        CGSize(width: panBase.width + panDelta.width, height: panBase.height + panDelta.height)
    }

    init(assistantMessage: LocalChatMessage, userMessage: LocalChatMessage, sessionId: UUID) {
        self.assistantMessage = assistantMessage
        self.userMessage = userMessage
        self.sessionId = sessionId
        let sid = sessionId
        _sessionMessages = Query(
            filter: #Predicate<LocalChatMessage> { $0.sessionId == sid },
            sort: \LocalChatMessage.createdAt
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch service.state {
            case .idle, .loading:
                loadingView

            case .failed(let msg):
                failedView(msg)

            case .ready(let annotations):
                if let image = firstImage {
                    GeometryReader { geo in
                        zoomableView(image: image, annotations: annotations, containerSize: geo.size)
                    }
                    .ignoresSafeArea()
                }
            }

            overlay
        }
        .fullScreenCover(isPresented: $showMemorizeHub) {
            LoroMemorizeHubView()
        }
        .task {
            await service.load(
                assistantMessage: assistantMessage,
                userMessage: userMessage,
                modelContext: modelContext
            )
        }
        .onAppear { pulsing = true }
    }

    // MARK: - Zoomable Photo

    private func zoomableView(image: UIImage, annotations: [AnnotationItem], containerSize: CGSize) -> some View {
        let frame = renderedImageFrame(for: image, in: containerSize)

        return ZStack {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize.width, height: containerSize.height)

                annotationLayer(annotations: annotations, imageFrame: frame, containerSize: containerSize)
            }
            .scaleEffect(currentZoom, anchor: .center)
            .offset(currentZoom > 1.0 ? currentPan : .zero)
        }
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { val in zoomDelta = val }
                    .onEnded { val in
                        zoomBase = min(5.0, max(1.0, zoomBase * val))
                        zoomDelta = 1.0
                        if zoomBase <= 1.0 { panBase = .zero; panDelta = .zero }
                    },
                DragGesture()
                    .onChanged { val in
                        guard currentZoom > 1.0 else { return }
                        panDelta = val.translation
                    }
                    .onEnded { _ in
                        panBase = currentPan
                        panDelta = .zero
                    }
            )
        )
    }

    // MARK: - Annotation Layer

    private func annotationLayer(annotations: [AnnotationItem], imageFrame: CGRect, containerSize: CGSize) -> some View {
        let positions = computeAllLabelPoints(annotations: annotations, imageFrame: imageFrame, containerSize: containerSize)

        return ZStack {
            Canvas { context, _ in
                for (index, item) in annotations.enumerated() {
                    let color = annotationPalette[index % annotationPalette.count]
                    let obj = objectPoint(item, imageFrame: imageFrame)
                    let lbl = positions[index]

                    var path = Path()
                    path.move(to: obj)
                    path.addLine(to: lbl)
                    context.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))

                    let dotSize: CGFloat = 8
                    let dotRect = CGRect(x: obj.x - dotSize / 2, y: obj.y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: dotRect), with: .color(color))
                    context.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .allowsHitTesting(false)

            ForEach(Array(annotations.enumerated()), id: \.offset) { index, item in
                let color = annotationPalette[index % annotationPalette.count]
                let lp = positions[index]
                let isActive = activeLabel == item.label
                let isExploding = explodingLabel == item.label
                let tapCount = tapCounts[item.label] ?? 0
                let growScale: CGFloat = 1.0 + CGFloat(min(tapCount, 4)) * 0.06

                Button {
                    handleLabelTap(item)
                } label: {
                    VStack(spacing: 1) {
                        Text(item.label.uppercased())
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        if !item.translation.isEmpty {
                            Text(item.translation)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .opacity(0.78)
                        }
                    }
                    .foregroundColor(isActive ? .black : color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isActive ? color : Color.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color, lineWidth: isActive ? 0 : 2)
                    )
                    .shadow(color: color.opacity(isActive ? 0.7 : 0.4), radius: isActive ? 10 : 4)
                    .scaleEffect(isExploding ? 2.2 : (isActive ? 1.12 : growScale))
                    .opacity(isExploding ? 0 : 1)
                    .animation(.spring(response: 0.22, dampingFraction: 0.5), value: isExploding)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isActive)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: tapCount)
                }
                .buttonStyle(.plain)
                .position(lp)
            }
        }
    }

    // MARK: - Tap Handling

    private func handleLabelTap(_ item: AnnotationItem) {
        speakLabel(item.label)
        let count = (tapCounts[item.label] ?? 0) + 1
        tapCounts[item.label] = count

        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            activeLabel = item.label
        }

        tapTimers[item.label]?.cancel()
        let label = item.label
        tapTimers[label] = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { activeLabel = nil }
                tapCounts[label] = 0
            }
        }

        if count >= 3 && !addedToMemory.contains(item.label) {
            addedToMemory.insert(item.label)
            triggerExplosion(for: item)
            addToMemoryQueue(item)
        }
    }

    private func triggerExplosion(for item: AnnotationItem) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
            explodingLabel = item.label
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.2)) { explodingLabel = nil }
        }
        withAnimation(.spring()) {
            memoryToast = "+1 added to memory queue!"
            memoryAddedCount += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.3)) { memoryToast = nil }
        }
    }

    private func addToMemoryQueue(_ item: AnnotationItem) {
        let normalised = item.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = (try? modelContext.fetch(FetchDescriptor<MemoryCard>())) ?? []
        if existing.contains(where: { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalised }) { return }

        let card = MemoryCard(
            content: item.label,
            translation: item.translation.isEmpty ? item.label : item.translation,
            audioSegmentPaths: [],
            exposureCount: 1,
            nextDueAt: MemorizeScheduler.nextDueAt(exposureCount: 1),
            isPaused: UserDefaults.standard.bool(forKey: "loro.vacationMode")
        )
        modelContext.insert(card)
        try? modelContext.save()
    }

    // MARK: - Overlay (UI controls above photo)

    private var overlay: some View {
        VStack(spacing: 0) {
            HStack {
                BackButton { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)

            Spacer()

            if let toast = memoryToast {
                Text(toast)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.yellow)
                    .clipShape(Capsule())
                    .shadow(color: Color.yellow.opacity(0.5), radius: 8)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: memoryToast)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 10) {
                voiceChatBar

                if memoryAddedCount > 0 {
                    Button {
                        showMemorizeHub = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 14, weight: .semibold))
                            Text(L("Go to memory queue (%d)", memoryAddedCount))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                        .shadow(color: Color.yellow.opacity(0.4), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: memoryAddedCount)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Voice Chat Bar

    private var voiceChatBar: some View {
        HStack(spacing: 12) {
            if voiceState == .transcribing || voiceState == .generating {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulsing ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: pulsing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let reply = lastVoiceReply {
                Text(reply)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if voiceState == .speaking {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(0.8)
                } else {
                    Button {
                        if let r = lastVoiceReply {
                            TTSService.shared.speak(text: r, messageId: UUID(), context: "sentence")
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.yellow.opacity(0.85))
                    }
                }
            } else {
                Text(L("Tap mic to chat about what you see"))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            micButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var micButton: some View {
        let isActive = voiceState == .recording
        return Button {
            if voiceState == .idle {
                voiceState = .recording
                try? voiceRecorder.start()
            } else if voiceState == .recording {
                handleVoiceStop()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? Color.red : Color.white.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(isActive ? Color.red.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1.5))
                    .scaleEffect(isActive ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isActive)

                Image(systemName: isActive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .disabled(voiceState == .transcribing || voiceState == .generating || voiceState == .speaking)
    }

    private func handleVoiceStop() {
        voiceState = .transcribing
        Task {
            let text = await voiceRecorder.stopAndTranscribe()
            guard !text.isEmpty else {
                await MainActor.run { voiceState = .idle }
                return
            }
            await MainActor.run { voiceState = .generating }

            let userMsg = LocalChatMessage(
                sessionId: sessionId,
                sender: .user,
                type: .text,
                textContent: text,
                imageLocalPaths: []
            )
            await MainActor.run {
                modelContext.insert(userMsg)
                try? modelContext.save()
            }

            let systemPrompt = PromptBuilder.visualSystemPrompt(profile: authState.profile)
            let history = Array(sessionMessages.filter { $0.textContent != nil }.suffix(10))

            do {
                let reply = try await openAI.sendMessage(
                    systemPrompt: systemPrompt,
                    history: history,
                    userText: text,
                    maxTokens: 300
                )
                let assistantMsg = LocalChatMessage(
                    sessionId: sessionId,
                    sender: .assistant,
                    type: .text,
                    textContent: reply,
                    imageLocalPaths: []
                )
                await MainActor.run {
                    modelContext.insert(assistantMsg)
                    try? modelContext.save()
                    lastVoiceReply = reply
                    voiceState = .speaking
                }
                TTSService.shared.speak(text: reply, messageId: assistantMsg.id, context: "scene")
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    if voiceState == .speaking { voiceState = .idle }
                }
            } catch {
                await MainActor.run { voiceState = .idle }
            }
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.yellow.opacity(0.15), lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(pulsing ? 360 : 0))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: pulsing)
                Image(systemName: "viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.yellow)
            }
            Text(L("Mapping the scene…"))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            Text(L("Professor Madrid is pinpointing each object"))
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text(L("Could not map the scene"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(L("Try Again")) {
                Task {
                    await service.load(
                        assistantMessage: assistantMessage,
                        userMessage: userMessage,
                        modelContext: modelContext
                    )
                }
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.yellow)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Geometry Helpers

    private func renderedImageFrame(for image: UIImage, in containerSize: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        let renderedSize: CGSize
        if imageAspect > containerAspect {
            let w = containerSize.width
            renderedSize = CGSize(width: w, height: w / imageAspect)
        } else {
            let h = containerSize.height
            renderedSize = CGSize(width: h * imageAspect, height: h)
        }

        let origin = CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
        return CGRect(origin: origin, size: renderedSize)
    }

    private func objectPoint(_ item: AnnotationItem, imageFrame: CGRect) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + item.x * imageFrame.width,
            y: imageFrame.minY + item.y * imageFrame.height
        )
    }

    private func estimatedLabelSize(_ text: String) -> CGSize {
        let charWidth: CGFloat = 9.0
        let hPadding: CGFloat = 24
        let height: CGFloat = 42
        let width = min(CGFloat(text.count) * charWidth + hPadding, 240)
        return CGSize(width: width, height: height)
    }

    private func computeAllLabelPoints(
        annotations: [AnnotationItem],
        imageFrame: CGRect,
        containerSize: CGSize
    ) -> [CGPoint] {
        let topSafeArea: CGFloat = 110
        let bottomSafeArea: CGFloat = 170
        let pushDist: CGFloat = min(imageFrame.width, imageFrame.height) * 0.28
        let total = annotations.count

        var points: [CGPoint] = annotations.enumerated().map { index, item in
            let objX = imageFrame.minX + item.x * imageFrame.width
            let objY = imageFrame.minY + item.y * imageFrame.height
            let dx = objX - imageFrame.midX
            let dy = objY - imageFrame.midY
            let mag = sqrt(dx * dx + dy * dy)

            var lx: CGFloat
            var ly: CGFloat
            if mag < 8 {
                lx = objX + pushDist
                ly = objY - pushDist
            } else {
                lx = objX + (dx / mag) * pushDist
                ly = objY + (dy / mag) * pushDist
            }

            let stagger = CGFloat(index - total / 2) * 20
            ly += stagger

            let sz = estimatedLabelSize(item.label)
            let hm = sz.width / 2 + 8
            let vm = sz.height / 2 + 4
            lx = max(hm, min(containerSize.width - hm, lx))
            ly = max(topSafeArea + vm, min(containerSize.height - bottomSafeArea - vm, ly))

            return CGPoint(x: lx, y: ly)
        }

        let sizes = annotations.map { estimatedLabelSize($0.label) }
        for _ in 0..<30 {
            var anyMoved = false
            for i in 0..<points.count {
                for j in (i + 1)..<points.count {
                    let si = sizes[i], sj = sizes[j]
                    let minSepX = (si.width + sj.width) / 2 + 8
                    let minSepY = (si.height + sj.height) / 2 + 6
                    let dx = points[j].x - points[i].x
                    let dy = points[j].y - points[i].y
                    let overlapX = minSepX - abs(dx)
                    let overlapY = minSepY - abs(dy)
                    guard overlapX > 0 && overlapY > 0 else { continue }
                    anyMoved = true
                    if overlapX < overlapY {
                        let push = overlapX / 2 + 1
                        let dir: CGFloat = dx >= 0 ? 1 : -1
                        points[i].x -= dir * push
                        points[j].x += dir * push
                    } else {
                        let push = overlapY / 2 + 1
                        let dir: CGFloat = dy >= 0 ? 1 : -1
                        points[i].y -= dir * push
                        points[j].y += dir * push
                    }
                }
            }
            for i in 0..<points.count {
                let sz = sizes[i]
                let hm = sz.width / 2 + 8
                let vm = sz.height / 2 + 4
                points[i].x = max(hm, min(containerSize.width - hm, points[i].x))
                points[i].y = max(topSafeArea + vm, min(containerSize.height - bottomSafeArea - vm, points[i].y))
            }
            if !anyMoved { break }
        }

        return points
    }

    // MARK: - TTS

    private func speakLabel(_ text: String) {
        TTSService.shared.speak(text: text, messageId: UUID(), context: "label")
    }
}
