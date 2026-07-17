import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

struct NewSessionView: View {
    enum InitialStep { case topicInput, streetViewPhotos }

    let initialStep: InitialStep
    let onSessionCreated: (LocalChatSession) -> Void
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: NewSessionStep
    @State private var topicText: String = ""
    @State private var topicRecorder = AudioRecorder()
    @State private var isRecordingTopic = false
    @State private var isTranscribingTopic = false

    @State private var streetImages: [UIImage] = []
    @State private var selectedStreetItems: [PhotosPickerItem] = []
    @State private var showStreetCamera = false
    @State private var showStreetPhotoPicker = false

    private enum NewSessionStep { case topicInput, streetViewPhotos }

    private let predefinedTopics = [
        "Past-tense verbs",
        "Spanish song",
        "I like, I don't like...",
        "Spatial adverbs (of place)",
        "Palabrotas..."
    ]

    init(initialStep: InitialStep, onSessionCreated: @escaping (LocalChatSession) -> Void) {
        self.initialStep = initialStep
        self.onSessionCreated = onSessionCreated
        _step = State(initialValue: initialStep == .topicInput ? .topicInput : .streetViewPhotos)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Group {
                    switch step {
                    case .topicInput:
                        topicInputContent
                    case .streetViewPhotos:
                        streetViewPhotosContent
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
            }
        }
        .onAppear {
            if initialStep == .streetViewPhotos && streetImages.isEmpty {
                showStreetCamera = true
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
        case .topicInput:        return L("Choose a Topic")
        case .streetViewPhotos:  return L("Street View")
        }
    }

    // MARK: - Step: Topic Input

    private var topicInputContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    Text(L("What topic do you want to learn about?"))
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
                    Text(L("e.g. \"ser vs estar\", \"travel vocabulary\"…"))
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
                    Text(L("Transcribing…"))
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
                    Text(L("Listening… tap mic to stop"))
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
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    private var predefinedTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Quick topics"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)

            FlowLayout(hSpacing: 10, vSpacing: 10) {
                ForEach(predefinedTopics, id: \.self) { topic in
                    Button(action: { topicText = topic }) {
                        Text(L(topic))
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
            Text(L("Start Conversation"))
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

    // MARK: - Step: Street View Photos

    private var streetViewPhotosContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Text(L("Add up to 4 photos of what is around you."))
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
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .foregroundColor(.white.opacity(0.25))

            Text(L("Visual learning: remember words 5× faster from photos of your real life."))
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
                    .font(.system(size: 22, design: .rounded))
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
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(L("Camera"))
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
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(L("Photos"))
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
                Text(L("Start Conversation"))
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
        AnalyticsService.shared.track(.sessionCreated(mode: SessionMode.visual.rawValue))
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
        AnalyticsService.shared.track(.sessionCreated(mode: mode.rawValue))
        onSessionCreated(session)
    }
}
