import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
    let session: LocalChatSession
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var threadParent: LocalChatMessage? = nil
    @State private var showThread: Bool = false
    @State private var pendingImages: [UIImage] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var audioRecorder = AudioRecorder()
    @State private var goalFlash = false
    @State private var showGoalEditor = false
    @State private var parrotMessage: LocalChatMessage? = nil
    @State private var annotationTarget: AnnotationTarget? = nil
    @State private var isVoiceSending = false
    @AppStorage("autoVoiceEnabled") private var autoVoiceEnabled: Bool = true

    private let openAI = ChatOpenAIService()

    private var rootMessages: [LocalChatMessage] {
        session.messages
            .filter { $0.threadParentId == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var canSend: Bool {
        !isGenerating && (
            !inputText.trimmingCharacters(in: .whitespaces).isEmpty ||
            !pendingImages.isEmpty
        )
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                messageList
                if let err = errorMessage {
                    errorBanner(err)
                }
                if !pendingImages.isEmpty {
                    imageStrip
                }
                inputBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton { dismiss() }
            }
            ToolbarItem(placement: .principal) {
                Text(session.title ?? session.topic ?? L(session.modeEnum.displayLabel))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.93, blue: 0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showGoalEditor = true
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 20))
                        .foregroundColor(.yellow.opacity(0.85))
                }
            }
        }
        .task { await openingMessage() }
        .sheet(isPresented: $showThread) {
            if let parent = threadParent {
                ThreadSheetView(session: session, parentMessage: parent)
                    .environment(authState)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 4,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadPhotos(from: newItems)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { image in
                pendingImages = [image]
                sendMessage()
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $parrotMessage) { msg in
            ParrotWordGridView(
                message: msg,
                sessionId: session.id,
                level: authState.profile?.levelEnum.displayLabel ?? L("Beginner")
            )
        }
        .fullScreenCover(item: $annotationTarget) { target in
            AnnotationCanvasView(
                assistantMessage: target.assistantMessage,
                userMessage: target.userMessage,
                sessionId: session.id
            )
        }
        .fullScreenCover(isPresented: $showGoalEditor) {
            GoalEditorSheet(
                initialGoal: session.sessionGoal ?? session.topic ?? ""
            ) { newGoal in
                updateSessionGoal(newGoal)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(rootMessages) { message in
                        let precedingImageMsg = userMessageWithImages(preceding: message)
                        MessageBubbleView(
                            message: message,
                            onReplyInThread: {
                                threadParent = message
                                showThread = true
                            },
                            onPlayFromHere: {
                                let items = rootMessages
                                    .compactMap { m -> (id: UUID, text: String)? in
                                        guard let t = m.textContent, !t.isEmpty else { return nil }
                                        return (id: m.id, text: t)
                                    }
                                TTSService.shared.toggleQueue(startingFrom: message.id, in: items)
                            },
                            onParrot: {
                                parrotMessage = message
                            },
                            onAnnotate: precedingImageMsg.map { userMsg in
                                {
                                    annotationTarget = AnnotationTarget(
                                        id: message.id,
                                        assistantMessage: message,
                                        userMessage: userMsg
                                    )
                                }
                            }
                        )
                        .id(message.id)
                    }
                    if isGenerating {
                        typingIndicator
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: rootMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isGenerating) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .offset(y: isGenerating ? -5 : 0)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.12), value: isGenerating)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pending Images Strip

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pendingImages.indices, id: \.self) { i in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: pendingImages[i])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            pendingImages.remove(at: i)
                            if pendingImages.isEmpty { selectedPhotoItems = [] }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("", text: $inputText, axis: .vertical)
                    .font(.system(size: 26, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppColors.inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppColors.inputBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Button(action: sendMessage) {
                    Image(systemName: isGenerating ? "hourglass" : "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(canSend ? .yellow : AppColors.textTertiary)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button {
                    guard !isGenerating else { return }
                    showCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text(L("Camera"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isGenerating ? AppColors.textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isGenerating ? Color.white.opacity(0.05) : Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .disabled(isGenerating)

                Button {
                    guard !isGenerating else { return }
                    showPhotoPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .semibold))
                        Text(L("Photos"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isGenerating ? AppColors.textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isGenerating ? Color.white.opacity(0.05) : Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .disabled(isGenerating)

                recordButton
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    // MARK: - Record Button (bottom row)

    private var recordButton: some View {
        let isRec = audioRecorder.isRecording
        let isBusy = isGenerating || isVoiceSending
        let activeColor = Color.red
        return Button {
            guard !isBusy else { return }
            if isRec {
                isVoiceSending = true
                Task {
                    let transcript = await audioRecorder.stopAndTranscribe()
                    await MainActor.run {
                        isVoiceSending = false
                        if !transcript.isEmpty {
                            inputText = transcript
                            sendMessage()
                        }
                    }
                }
            } else {
                TTSService.shared.stop()
                try? audioRecorder.start()
            }
        } label: {
            HStack(spacing: 8) {
                if isVoiceSending {
                    ProgressView().tint(.white).scaleEffect(0.75)
                    Text(L("Sending…"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                } else if isRec {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text(L("Stop"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text(L("Record"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
            }
            .foregroundColor(isBusy && !isVoiceSending ? AppColors.textTertiary : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(isRec ? activeColor.opacity(0.85) : (isBusy ? Color.white.opacity(0.05) : Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isRec ? activeColor : Color.white.opacity(0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .disabled(isBusy)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.red.opacity(0.9))
            Spacer()
            Button(L("Dismiss")) { errorMessage = nil }
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(14)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Goal Banner

    private var goalBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.yellow.opacity(0.8))

            Text(session.sessionGoal ?? session.topic ?? L("Free conversation"))
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                showGoalEditor = true
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 26))
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(goalFlash ? Color.yellow.opacity(0.18) : AppColors.cardBackground)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.yellow.opacity(goalFlash ? 0.5 : 0.13)), alignment: .bottom)
        .animation(.easeInOut(duration: 0.35), value: goalFlash)
    }

    private func updateSessionGoal(_ newGoal: String) {
        session.sessionGoal = newGoal
        session.updatedAt = Date()
        try? modelContext.save()
        flashGoalBanner()
        Task {
            if let userId = authState.userId {
                await SupabaseSyncService.shared.upsertSession(session, userId: userId)
            }
        }
    }

    private func flashGoalBanner() {
        goalFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { goalFlash = false }
        }
    }

    // MARK: - Message Actions

    private func openingMessage() async {
        guard rootMessages.isEmpty else { return }
        switch session.modeEnum {
        case .visual:
            if let images = StreetViewPhotoStore.shared.consume(for: session.id), !images.isEmpty {
                await openingMessageWithPhotos(images)
            }
        case .topic:
            await generateAssistantReply(userText: nil, imageData: [])
        }
    }

    private func openingMessageWithPhotos(_ images: [UIImage]) async {
        let imageData = images.compactMap { $0.jpegData(compressionQuality: 0.72) }
        let imagePaths = saveImages(images, sessionId: session.id)

        let userMsg = LocalChatMessage(
            sessionId: session.id,
            sender: .user,
            type: .image,
            textContent: nil,
            imageLocalPaths: imagePaths
        )
        addMessage(userMsg)

        Task {
            if let label = try? await openAI.sendMessage(
                systemPrompt: PromptBuilder.visualSceneLabelPrompt(),
                history: [],
                userText: "",
                imageData: imageData,
                maxTokens: 12
            ), !label.isEmpty {
                await MainActor.run {
                    session.title = label
                    session.updatedAt = Date()
                    try? modelContext.save()
                    Task {
                        if let uid = authState.userId {
                            await SupabaseSyncService.shared.upsertSession(session, userId: uid)
                        }
                    }
                }
            }
        }

        await generateAssistantReply(userText: nil, imageData: imageData)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        let images = pendingImages
        inputText = ""
        pendingImages = []
        selectedPhotoItems = []

        let type: MessageType = images.isEmpty ? .text : (text.isEmpty ? .image : .mixed)
        let imagePaths = saveImages(images, sessionId: session.id)
        let imageData = images.compactMap { $0.jpegData(compressionQuality: 0.72) }

        let msg = LocalChatMessage(
            sessionId: session.id,
            sender: .user,
            type: type,
            textContent: text.isEmpty ? nil : text,
            imageLocalPaths: imagePaths
        )
        addMessage(msg)
        Task { await generateAssistantReply(userText: text.isEmpty ? nil : text, imageData: imageData) }
    }

    private func loadPhotos(from items: [PhotosPickerItem]) {
        Task {
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    loaded.append(img)
                }
            }
            await MainActor.run { pendingImages = loaded }
        }
    }

    private func saveImages(_ images: [UIImage], sessionId: UUID) -> [String] {
        guard !images.isEmpty else { return [] }
        let relativeDir = "esp-images/\(sessionId.uuidString)"
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docsDir.appendingPathComponent(relativeDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return images.compactMap { img in
            let filename = UUID().uuidString + ".jpg"
            let url = dir.appendingPathComponent(filename)
            guard let data = img.jpegData(compressionQuality: 0.72) else { return nil }
            try? data.write(to: url)
            return relativeDir + "/" + filename
        }
    }

    // MARK: - LLM

    private func generateAssistantReply(userText: String?, imageData: [Data]) async {
        isGenerating = true
        errorMessage = nil

        let systemPrompt: String
        switch session.modeEnum {
        case .topic:
            systemPrompt = PromptBuilder.topicSystemPrompt(
                profile: authState.profile,
                topic: session.sessionGoal ?? session.topic
            )
        case .visual:
            systemPrompt = PromptBuilder.visualSystemPrompt(
                profile: authState.profile,
                goal: session.sessionGoal ?? session.topic
            )
        }

        let history = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
        let topic = session.sessionGoal ?? session.topic ?? "español general"
        let openingInstruction = "Empieza ya. Sin saludo. Primera frase directamente en español practicando: \(topic)."
        let userInput = userText ?? (imageData.isEmpty ? openingInstruction : "")

        do {
            var reply = try await openAI.sendMessage(
                systemPrompt: systemPrompt,
                history: history,
                userText: userInput,
                imageData: imageData,
                maxTokens: authState.profile?.levelEnum.maxTokens ?? 300
            )

            let assistantMsg = LocalChatMessage(
                sessionId: session.id,
                sender: .assistant,
                type: .text,
                textContent: reply
            )
            addMessage(assistantMsg)
            if autoVoiceEnabled && !TTSService.shared.isQueueActive {
                let ttsContext = imageData.isEmpty ? "sentence" : "scene"
                TTSService.shared.speak(text: reply, messageId: assistantMsg.id, context: ttsContext)
            }

            let lastUserMsg = rootMessages.last(where: { $0.isUser })

            if let userText, !userText.isEmpty {
                let sessionRef   = session
                let contextRef   = modelContext
                let authStateRef = authState
                GoalClassifierService.shared.classify(
                    userMessage: userText,
                    tutorReply: reply,
                    currentGoal: session.sessionGoal ?? session.topic ?? ""
                ) { newGoal in
                    sessionRef.sessionGoal = newGoal
                    sessionRef.updatedAt = Date()
                    try? contextRef.save()
                    Task {
                        if let userId = authStateRef.userId {
                            await SupabaseSyncService.shared.upsertSession(sessionRef, userId: userId)
                        }
                    }
                }
            }

            ProfileAnalystService.shared.analyzeExchange(
                userMessage: lastUserMsg,
                tutorMessage: assistantMsg,
                session: session,
                authState: authState
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    private func addMessage(_ message: LocalChatMessage) {
        modelContext.insert(message)
        session.messages.append(message)
        session.messageCount = session.messages.count
        let isOpeningAssistantMessage = session.messages.count == 1 && message.isAssistant
        if !isOpeningAssistantMessage {
            session.lastMessagePreview = message.textContent.map { String($0.prefix(100)) }
        }
        session.lastMessageAt = message.createdAt
        session.updatedAt = Date()
        try? modelContext.save()
        Task {
            await SupabaseSyncService.shared.insertMessage(message)
            if let userId = authState.userId {
                await SupabaseSyncService.shared.upsertSession(session, userId: userId)
            }
        }
    }

    private func userMessageWithImages(preceding assistantMessage: LocalChatMessage) -> LocalChatMessage? {
        guard assistantMessage.isAssistant else { return nil }
        let msgs = rootMessages
        guard let idx = msgs.firstIndex(where: { $0.id == assistantMessage.id }), idx > 0 else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            let msg = msgs[i]
            if msg.isUser && !msg.imageLocalPaths.isEmpty { return msg }
            if msg.isAssistant { break }
        }
        return nil
    }
}

struct AnnotationTarget: Identifiable {
    let id: UUID
    let assistantMessage: LocalChatMessage
    let userMessage: LocalChatMessage
}

struct GoalEditorSheet: View {
    let initialGoal: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var recorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isTranscribing = false

    init(initialGoal: String, onSave: @escaping (String) -> Void) {
        self.initialGoal = initialGoal
        self.onSave = onSave
        _text = State(initialValue: initialGoal)
    }

    var canSave: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L("What are we focusing on in this session?"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)

                        HStack(alignment: .top, spacing: 12) {
                            TextField(L("e.g. past tense, ser vs estar, travel vocabulary…"), text: $text, axis: .vertical)
                                .font(.system(size: 20, weight: .regular, design: .rounded))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(3...7)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                                .background(AppColors.inputBackground)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.inputBorder, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            micButton
                        }

                        if isTranscribing {
                            HStack(spacing: 8) {
                                ProgressView().tint(.yellow).scaleEffect(0.85)
                                Text(L("Transcribing…"))
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.yellow.opacity(0.8))
                            }
                        } else if isRecording {
                            HStack(spacing: 8) {
                                Circle().fill(Color.red).frame(width: 9, height: 9)
                                Text(L("Listening… tap mic to stop"))
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                        }

                        Text(L("Speak your focus or type it. Professor Madrid will jump straight into teaching it from the very first message."))
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                            .lineSpacing(4)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(L("Session Focus"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppColors.backgroundTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackButton { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Save")) {
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { onSave(trimmed) }
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(canSave ? .yellow : AppColors.textTertiary)
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var micButton: some View {
        Button {
            guard !isTranscribing else { return }
            if isRecording {
                isRecording = false
                isTranscribing = true
                Task {
                    let transcript = await recorder.stopAndTranscribe()
                    await MainActor.run {
                        if !transcript.isEmpty { text = transcript }
                        isTranscribing = false
                    }
                }
            } else {
                do {
                    try recorder.start()
                    isRecording = true
                } catch {}
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : isTranscribing ? Color.yellow.opacity(0.2) : AppColors.inputBackground)
                    .frame(width: 58, height: 58)
                    .overlay(Circle().stroke(isRecording ? Color.red.opacity(0.4) : AppColors.inputBorder, lineWidth: 1))
                if isTranscribing {
                    ProgressView().tint(.yellow).scaleEffect(0.9)
                } else if isRecording {
                    VoiceWaveformView(audioLevel: recorder.audioLevel, color: .white, barCount: 5, maxHeight: 24, barWidth: 3, spacing: 3)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .disabled(isTranscribing)
    }
}
