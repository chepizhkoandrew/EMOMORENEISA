import SwiftUI
import SwiftData
import PhotosUI

struct ChatView: View {
    let session: LocalChatSession
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var showGoalEditor = false
    @State private var parrotMessage: LocalChatMessage? = nil
    @State private var annotationTarget: AnnotationTarget? = nil
    @State private var isVoiceSending = false
    @State private var suggestedReplies: [String] = []
    @State private var showSuggestionsSheet = false
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
            if session.modeEnum == .roleplay, let scenePath = session.roleplaySceneImagePath,
               let image = UIImage(contentsOfFile: resolvedRoleplaySceneURL(scenePath).path) {
                // GeometryReader gives the image a genuinely fixed, known frame
                // to fill. Without it, `scaledToFill()` computes its own ideal
                // size to preserve the image's aspect ratio while covering
                // both axes — deliberately WIDER than the screen along one
                // axis, that's the whole point of "fill" — and a bare
                // `.frame(maxWidth: .infinity)` only sets an upper BOUND, it
                // doesn't clamp back down to the actual proposed size. That
                // oversized ideal width leaked upward into this entire ZStack
                // (and everything else inside it), which is what was causing
                // every row on this screen to render clipped at both edges.
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
            } else {
                AppBackground()
            }

            VStack(spacing: 0) {
                messageList
                if let err = errorMessage {
                    errorBanner(err)
                }
                if !pendingImages.isEmpty {
                    imageStrip
                }
                if !suggestedReplies.isEmpty && !isGenerating {
                    suggestionsButton
                }
                inputBar
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: inputText) { _, newValue in
            if !newValue.isEmpty && !suggestedReplies.isEmpty {
                suggestedReplies = []
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
        }
        .withBurgerMenu(extraItems: [
            BurgerMenuItem(label: "Edit Goal", systemImage: "scope") { showGoalEditor = true }
        ])
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
                LazyVStack(alignment: .leading, spacing: 14) {
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
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: rootMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isGenerating) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
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

    // MARK: - Suggested Replies (Roleplay)

    // A single trigger button rather than a horizontally-scrolling chip row —
    // full-sentence suggestions don't fit legibly in a one-line scroller, and
    // there's no way to see all 3 at a glance to actually compare them.
    private var suggestionsButton: some View {
        Button {
            showSuggestionsSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L("Suggested replies"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("\(suggestedReplies.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.yellow)
                    .clipShape(Capsule())
            }
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
        .sheet(isPresented: $showSuggestionsSheet) {
            suggestionsSheetContent
        }
    }

    private var suggestionsSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(suggestedReplies, id: \.self) { suggestion in
                        Button {
                            inputText = suggestion
                            suggestedReplies = []
                            showSuggestionsSheet = false
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(AppColors.textPrimary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(AppColors.inputBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(AppColors.inputBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(AppColors.backgroundTop)
            .navigationTitle(L("Suggested replies"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Close")) { showSuggestionsSheet = false }
                        .foregroundColor(.yellow)
                }
            }
        }
        .presentationDetents([.medium])
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
                                .font(.system(size: 18, design: .rounded))
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
        .frame(maxWidth: .infinity)
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
                        .font(.system(size: 40, design: .rounded))
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
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(L("Stop"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
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

    private func updateSessionGoal(_ newGoal: String) {
        session.sessionGoal = newGoal
        session.updatedAt = Date()
        try? modelContext.save()
        Task {
            if let userId = authState.userId {
                await SupabaseSyncService.shared.upsertSession(session, userId: userId)
            }
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
        case .roleplay:
            await generateRoleplayReply(userText: nil)
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
        suggestedReplies = []

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

    private func resolvedRoleplaySceneURL(_ relativePath: String) -> URL {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docsDir.appendingPathComponent(relativePath)
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
        guard session.modeEnum != .roleplay else {
            await generateRoleplayReply(userText: userText)
            return
        }
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
        case .roleplay:
            systemPrompt = "" // unreachable — handled by the guard above
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

    // MARK: - Roleplay LLM

    private func generateRoleplayReply(userText: String?) async {
        isGenerating = true
        errorMessage = nil

        let objectLabel = session.roleplayObjectLabel ?? "a mysterious guest"
        let environmentLabel = session.roleplayEnvironmentLabel ?? "a cozy studio"
        let topic = session.topic ?? "everyday life"

        let systemPrompt = PromptBuilder.roleplaySystemPrompt(
            profile: authState.profile,
            objectLabel: objectLabel,
            environmentLabel: environmentLabel,
            topic: topic
        )

        let history = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
        let openingInstruction = "Empieza el programa ya. Preséntate brevemente, presenta a tu invitado de hoy y deja que reaccione."
        let userInput = userText ?? openingInstruction
        // A round can now be a variable-length sequence of up to ~4 lines
        // (dynamic turn-taking) rather than a fixed Madrid+Object pair, so
        // give the model some extra headroom over the normal per-turn budget.
        let baseMaxTokens = authState.profile?.levelEnum.maxTokens ?? 300
        let roleplayMaxTokens = Int(Double(baseMaxTokens) * 1.4)

        do {
            let raw = try await ProxyClient.shared.chatRoleplay(
                systemPrompt: systemPrompt,
                history: history,
                userText: userInput,
                maxTokens: roleplayMaxTokens
            )
            let segments = RoleplayResponseParser.parse(raw)
            let objectVoiceName = session.roleplayObjectVoice ?? RoleplayContent.voiceForObject(objectLabel)

            var turnItems: [(id: UUID, text: String, voice: (languageCode: String, voiceName: String)?)] = []
            for segment in segments {
                let msg = LocalChatMessage(
                    sessionId: session.id,
                    sender: .assistant,
                    type: .text,
                    textContent: segment.text,
                    speakerId: segment.speaker
                )
                addMessage(msg)

                let voice: (languageCode: String, voiceName: String)? =
                    segment.speaker == "object" ? (languageCode: "es-ES", voiceName: objectVoiceName) : nil
                turnItems.append((id: msg.id, text: segment.text, voice: voice))
            }

            if autoVoiceEnabled, !turnItems.isEmpty {
                TTSService.shared.speakTurn(turnItems)
            }

            refreshSuggestedReplies(objectLabel: objectLabel, topic: topic)
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    // Fire-and-forget: kicks off the 3 suggested-reply chips for the student's
    // next turn without blocking the round from being marked done. Best-effort
    // — a failure just means no chips show up until the following round.
    private func refreshSuggestedReplies(objectLabel: String, topic: String) {
        let recentHistory = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
        let level = authState.profile?.levelEnum.displayLabel ?? L("Beginner")
        Task {
            if let replies = await SuggestedRepliesService.shared.generateReplies(
                history: recentHistory,
                objectLabel: objectLabel,
                topic: topic,
                level: level
            ) {
                suggestedReplies = replies
            }
        }
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
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .disabled(isTranscribing)
    }
}
