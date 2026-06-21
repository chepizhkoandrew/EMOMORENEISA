import SwiftUI
import SwiftData
import PhotosUI

struct NewSessionView: View {
    let onSessionCreated: (LocalChatSession) -> Void
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: NewSessionStep = .modeSelection
    @State private var topicText: String = ""
    @State private var topicRecorder = AudioRecorder()
    @State private var isRecordingTopic = false
    @State private var isTranscribingTopic = false
    @State private var topicCardPressed = false
    @State private var streetCardPressed = false

    @State private var streetImages: [UIImage] = []
    @State private var selectedStreetItems: [PhotosPickerItem] = []
    @State private var showStreetCamera = false
    @State private var showStreetPhotoPicker = false

    private enum NewSessionStep { case modeSelection, topicInput, streetViewPhotos }

    private let predefinedTopics = [
        "Past-tense verbs",
        "Spanish song",
        "I like, I don't like...",
        "Spatial adverbs (of place)",
        "Palabrotas..."
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    switch step {
                    case .modeSelection:
                        modeSelectorContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .topicInput:
                        topicInputContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    case .streetViewPhotos:
                        streetViewPhotosContent
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.spring(response: 0.40, dampingFraction: 0.85), value: step)
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(step == .modeSelection ? .inline : .large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step == .modeSelection {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.white)
                            .font(.system(size: 17, design: .rounded))
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.85)) {
                                step = .modeSelection
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 17, design: .rounded))
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showStreetPhotoPicker,
            selection: $selectedStreetItems,
            maxSelectionCount: 4,
            matching: .images
        )
        .onChange(of: selectedStreetItems) { _, newItems in
            Task {
                var loaded: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        loaded.append(img)
                    }
                }
                await MainActor.run { streetImages = loaded }
            }
        }
        .fullScreenCover(isPresented: $showStreetCamera) {
            CameraPickerView { image in
                if streetImages.count < 4 {
                    streetImages.append(image)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var navTitle: String {
        switch step {
        case .modeSelection:     return ""
        case .topicInput:        return "Choose a Topic"
        case .streetViewPhotos:  return "Street View"
        }
    }

    // MARK: - Step 1: Mode Selection

    private var modeSelectorContent: some View {
        GeometryReader { geo in
            let illustrationH = min(geo.size.height * 0.21, 170.0)
            let cardH = illustrationH + 32
            let dogH: CGFloat = min(geo.size.height * 0.33, 260.0)
            let dogOverlap: CGFloat = 180.0

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .bottom, spacing: 12) {
                            Image("professor_dog")
                                .resizable()
                                .scaledToFit()
                                .frame(height: dogH)

                            staticSpeechBubble
                                .padding(.bottom, 110)
                        }
                        .padding(.horizontal, 20)

                        topicModeCard(cardH: cardH, illustrationH: illustrationH)
                            .padding(.horizontal, 20)
                            .padding(.top, dogOverlap)
                    }
                    .frame(height: cardH + dogOverlap)

                    streetViewCard(cardH: cardH, illustrationH: illustrationH)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    Spacer(minLength: geo.safeAreaInsets.bottom + 24)
                }
                .frame(minHeight: geo.size.height)
            }
        }
    }

    private var staticSpeechBubble: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.yellow)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            SpeechTailShape()
                .fill(Color.yellow)
                .frame(width: 11, height: 9)
                .offset(x: -10, y: 2)

            Text("How do you\nwant to learn?")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
    }

    private func topicModeCard(cardH: CGFloat, illustrationH: CGFloat) -> some View {
        let overflow: CGFloat = 10
        return Button(action: {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.85)) {
                step = .topicInput
            }
        }) {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.82, blue: 0.08),
                            Color(red: 0.88, green: 0.60, blue: 0.02),
                            Color(red: 0.72, green: 0.42, blue: 0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: cardH)

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(height: cardH)

                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Choose a topic")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                        Text("Talk with tutor via text and voice messages")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.black.opacity(0.52))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image("topic_conversation")
                        .resizable()
                        .scaledToFit()
                        .frame(height: illustrationH + overflow)
                        .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: cardH, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardH)
            .scaleEffect(topicCardPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: topicCardPressed)
            .shadow(color: Color.yellow.opacity(0.45), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in topicCardPressed = true }
                .onEnded { _ in topicCardPressed = false }
        )
    }

    private func streetViewCard(cardH: CGFloat, illustrationH: CGFloat) -> some View {
        let overflow: CGFloat = 10
        return Button(action: {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.85)) {
                step = .streetViewPhotos
            }
        }) {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.58, blue: 1.0),
                            Color(red: 0.06, green: 0.38, blue: 0.90),
                            Color(red: 0.04, green: 0.22, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: cardH)

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.5)
                    .frame(height: cardH)

                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Street view")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Upload a photo of what is around you")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image("street_view")
                        .resizable()
                        .scaledToFit()
                        .frame(height: illustrationH + overflow)
                        .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: cardH, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardH)
            .scaleEffect(streetCardPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: streetCardPressed)
            .shadow(color: Color.blue.opacity(0.45), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in streetCardPressed = true }
                .onEnded { _ in streetCardPressed = false }
        )
    }

    // MARK: - Step 2: Topic Input

    private var topicInputContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    Text("What topic do you want to learn about?")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    topicField

                    predefinedTopicsSection
                }
                .padding(24)
            }

            startConversationBar
        }
    }

    private var topicField: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if topicText.isEmpty {
                    Text("e.g. \"ser vs estar\", \"travel vocabulary\"…")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextField("", text: $topicText, axis: .vertical)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2...4)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            .background(AppColors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.inputBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            topicMicButton
        }
        .overlay(alignment: .bottomLeading) {
            if isTranscribingTopic {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(0.85)
                    Text("Transcribing…")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.yellow.opacity(0.8))
                }
                .padding(.leading, 4)
                .offset(y: 28)
            } else if isRecordingTopic {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                    Text("Listening… tap mic to stop")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.red.opacity(0.8))
                }
                .padding(.leading, 4)
                .offset(y: 28)
            }
        }
        .padding(.bottom, (isTranscribingTopic || isRecordingTopic) ? 28 : 0)
    }

    private var topicMicButton: some View {
        Button {
            guard !isTranscribingTopic else { return }
            if isRecordingTopic {
                isRecordingTopic = false
                isTranscribingTopic = true
                Task {
                    let transcript = await topicRecorder.stopAndTranscribe()
                    await MainActor.run {
                        if !transcript.isEmpty {
                            topicText = transcript
                        }
                        isTranscribingTopic = false
                    }
                }
            } else {
                do {
                    try topicRecorder.start()
                    isRecordingTopic = true
                } catch {}
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isRecordingTopic ? Color.red : isTranscribingTopic ? Color.yellow.opacity(0.2) : AppColors.inputBackground)
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .stroke(isRecordingTopic ? Color.red.opacity(0.4) : AppColors.inputBorder, lineWidth: 1)
                    )
                if isTranscribingTopic {
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(0.9)
                } else if isRecordingTopic {
                    VoiceWaveformView(
                        audioLevel: topicRecorder.audioLevel,
                        color: .white,
                        barCount: 5,
                        maxHeight: 24,
                        barWidth: 3,
                        spacing: 3
                    )
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private var predefinedTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick topics")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)

            FlowLayout(hSpacing: 10, vSpacing: 10) {
                ForEach(predefinedTopics, id: \.self) { topic in
                    Button(action: { topicText = topic }) {
                        Text(topic)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(topicText == topic ? .black : AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(topicText == topic ? Color.yellow : AppColors.inputBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(topicText == topic ? Color.yellow : AppColors.inputBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: topicText == topic)
                }
            }
        }
    }

    private var startConversationBar: some View {
        let disabled = isTranscribingTopic || topicText.trimmingCharacters(in: .whitespaces).isEmpty
        return Button(action: { createSession(mode: .topic) }) {
            Text("Start Conversation")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(disabled ? Color.yellow.opacity(0.35) : Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: disabled ? .clear : Color.yellow.opacity(0.4), radius: 12, y: 4)
        }
        .disabled(disabled)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    // MARK: - Step 3: Street View Photos

    private var streetViewPhotosContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Add up to 4 photos of what is around you.")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    if streetImages.isEmpty {
                        streetEmptyState
                    } else {
                        streetPhotoGrid
                    }
                }
                .padding(24)
            }

            streetActionBar
        }
    }

    private var streetEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64, weight: .thin))
                .foregroundColor(.white.opacity(0.25))

            Text("Visual learning: remember words 5× faster from photos of your real life.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var streetPhotoGrid: some View {
        VStack(spacing: 12) {
            let rows = stride(from: 0, to: streetImages.count, by: 2).map {
                Array(streetImages[$0..<min($0 + 2, streetImages.count)])
            }
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 12) {
                    let row = rows[rowIdx]
                    ForEach(row.indices, id: \.self) { colIdx in
                        let globalIdx = rowIdx * 2 + colIdx
                        streetPhotoThumb(image: row[colIdx], index: globalIdx)
                    }
                    if row.count == 1 {
                        if streetImages.count < 4 {
                            addMoreButton
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            if streetImages.count % 2 == 0 && streetImages.count < 4 {
                HStack {
                    addMoreButton
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func streetPhotoThumb(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                streetImages.remove(at: index)
                if streetImages.isEmpty { selectedStreetItems = [] }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .offset(x: 6, y: -6)
        }
        .frame(maxWidth: .infinity)
    }

    private var addMoreButton: some View {
        Button {
            showStreetCamera = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(AppColors.inputBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.inputBorder, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var streetActionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    showStreetCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Camera")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(streetImages.count >= 4)
                .opacity(streetImages.count >= 4 ? 0.35 : 1.0)

                Button {
                    showStreetPhotoPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Photos")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(streetImages.count >= 4)
                .opacity(streetImages.count >= 4 ? 0.35 : 1.0)
            }

            Button(action: startStreetViewSession) {
                Text("Start Conversation")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(streetImages.isEmpty ? Color.yellow.opacity(0.35) : Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: streetImages.isEmpty ? .clear : Color.yellow.opacity(0.4), radius: 12, y: 4)
            }
            .disabled(streetImages.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    // MARK: - Session Creation

    private func startStreetViewSession() {
        guard !streetImages.isEmpty else { return }
        guard let userId = authState.userId else { return }
        let session = LocalChatSession(userId: userId, mode: .visual, title: nil, topic: nil)
        modelContext.insert(session)
        try? modelContext.save()
        StreetViewPhotoStore.shared.set(streetImages, for: session.id)
        Task {
            await SupabaseSyncService.shared.upsertSession(session, userId: userId)
        }
        onSessionCreated(session)
    }

    private func createSession(mode: SessionMode) {
        if isRecordingTopic {
            isRecordingTopic = false
            topicRecorder.cancel()
        }
        guard let userId = authState.userId else { return }
        let topicStr = mode == .topic ? topicText.trimmingCharacters(in: .whitespaces) : ""
        let nonEmptyTopic: String? = topicStr.isEmpty ? nil : topicStr
        let session = LocalChatSession(
            userId: userId,
            mode: mode,
            title: nonEmptyTopic,
            topic: nonEmptyTopic
        )
        modelContext.insert(session)
        try? modelContext.save()
        Task {
            await SupabaseSyncService.shared.upsertSession(session, userId: userId)
        }
        onSessionCreated(session)
    }
}
