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
    @State private var lessonState: LessonSessionState? = nil
    @State private var practiceSession: PracticeSession? = nil
    @AppStorage("autoVoiceEnabled") private var autoVoiceEnabled: Bool = true

    private let openAI = ChatOpenAIService()

    private var rootMessages: [LocalChatMessage] {
        session.messages
            .filter { $0.threadParentId == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // Real short name for the guest's chat-bubble label — same source the
    // "pass the word" buttons and the turn classifier use, so what's shown on
    // screen matches what the student can actually address by name.
    private var roleplayGuestDisplayName: String {
        shortGuestName(L(session.roleplayObjectLabel ?? ""))
    }

    /// "Edit Goal" only makes sense where `session.sessionGoal`/`topic`
    /// actually drives the assistant's behavior (Topic/Visual/Free Forum).
    /// Roleplay's target is the object/environment picked at session
    /// creation, not this field — and Roleplay already lets a student steer
    /// the conversation just by saying so in chat, since the character reads
    /// the full conversation and responds naturally rather than being locked
    /// to a fixed subject. Say It Better is the same story: its content is a
    /// fixed, scripted `lessonId` (chapters/quiz authored ahead of time), not
    /// anything `session.sessionGoal` drives.
    private var goalEditorMenuItems: [BurgerMenuItem] {
        guard session.modeEnum != .roleplay, session.modeEnum != .lesson else { return [] }
        return [BurgerMenuItem(label: "Edit Goal", systemImage: "scope") { showGoalEditor = true }]
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
                if session.modeEnum == .lesson, let dock = lessonState, !dock.isCompleted,
                   dock.currentPhase == .beforePracticeCheckpoint || dock.currentPhase == .afterPracticeCheckpoint
                    || dock.currentPhase == .practice {
                    nextStepsDock(for: dock)
                } else if (!suggestedReplies.isEmpty || session.modeEnum == .roleplay) && !isGenerating {
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
        .withBurgerMenu(extraItems: goalEditorMenuItems)
        .task {
            setUpLessonStateIfNeeded()
            await openingMessage()
        }
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
        .fullScreenCover(item: $practiceSession) { ps in
            PracticeCarouselView(
                session: ps,
                onFinish: { result in
                    practiceSession = nil
                    lessonState?.recordPracticeResult(result)
                    Task { await generateLessonReply(userText: nil) }
                },
                onCancel: {
                    practiceSession = nil
                    lessonState?.cancelPractice()
                },
                onProgress: { index, answers in
                    lessonState?.recordPracticeProgress(index: index, answers: answers)
                }
            )
        }
        .onChange(of: lessonState?.currentPhase) { _, phase in
            // Fires when a later chapter's explain beat starts (not reachable
            // with v1's single-chapter content, but keeps the multi-chapter
            // path correct for when Word Swap topics add a second chapter).
            guard phase == .explain, (lessonState?.currentChapterIndex ?? 0) > 0 else { return }
            Task { await beginOrResumeLesson() }
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
                            },
                            highlightTerms: lessonState?.highlights(forMessageId: message.id) ?? [],
                            practiceSummary: lessonState?.practiceSummary(forMessageId: message.id),
                            guestDisplayName: roleplayGuestDisplayName
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
                scrollToFocusPoint(proxy)
            }
            .onChange(of: rootMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: isGenerating) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    scrollToFocusPoint(proxy)
                }
            }
            .onChange(of: TTSService.shared.playingMessageId) { _, newValue in
                guard let newValue else { return }
                session.lastPlayedMessageId = newValue
                try? modelContext.save()
            }
        }
    }

    /// Picks up where the learner actually left off instead of always
    /// jumping to the newest message:
    /// - Brand-new session (nothing played yet) → the first message.
    /// - Returning mid-lesson → the last message that was played (or is
    ///   currently playing), so what's on screen matches what's audible.
    /// - Lesson fully played through → that "last played" message is by
    ///   definition the last message, so this naturally lands at the bottom.
    private func scrollToFocusPoint(_ proxy: ScrollViewProxy) {
        if let lastPlayedId = session.lastPlayedMessageId,
           rootMessages.contains(where: { $0.id == lastPlayedId }) {
            let isLastMessage = rootMessages.last?.id == lastPlayedId
            proxy.scrollTo(lastPlayedId, anchor: isLastMessage ? .bottom : .top)
        } else if let firstId = rootMessages.first?.id {
            proxy.scrollTo(firstId, anchor: .top)
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
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
                                .font(.system(size: 20, weight: .regular, design: .rounded))
                                .foregroundColor(AppColors.textPrimary)
                                .lineSpacing(5)
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

                    if session.modeEnum == .roleplay {
                        passWordButton(
                            label: "🎙️ \(L("Pass the word to")) Madrid",
                            speaker: "madrid"
                        )
                        passWordButton(
                            label: "🎙️ \(L("Pass the word to")) \(roleplayGuestDisplayName)",
                            speaker: "object"
                        )
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

    private func passWordButton(label: String, speaker: String) -> some View {
        Button {
            passWordTo(speaker)
        } label: {
            Text(label)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // Extracts a short spoken name for the "pass the word" buttons — most
    // curated guests are "Name, description" (e.g. "Cleopatra, the last
    // pharaoh of Egypt"), so the part before the comma reads naturally. The
    // grounded/everyday archetypes (e.g. "a market thief looking for one more
    // score") have no proper name, so those fall back to a generic label
    // rather than an awkward "a a market thief...".
    private func shortGuestName(_ label: String) -> String {
        if let commaIndex = label.firstIndex(of: ",") {
            return String(label[label.startIndex..<commaIndex]).trimmingCharacters(in: .whitespaces)
        }
        let lower = label.lowercased()
        if lower.hasPrefix("a ") || lower.hasPrefix("an ") || lower.hasPrefix("the ") {
            return L("the guest")
        }
        return label
    }

    // Explicit hand-off, chosen by the student rather than inferred by the
    // turn classifier — so the next speaker is forced directly instead of
    // asking the classifier to guess who a canned line was addressed to.
    private func passWordTo(_ speaker: String) {
        let guestName = roleplayGuestDisplayName
        let text = speaker == "madrid" ? "Madrid, cuéntanos tú." : "\(guestName), ¿tú qué dices?"

        showSuggestionsSheet = false
        suggestedReplies = []

        let msg = LocalChatMessage(
            sessionId: session.id,
            sender: .user,
            type: .text,
            textContent: text
        )
        addMessage(msg)
        Task { await generateRoleplayReply(userText: text, forcedFirstSpeaker: speaker) }
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
        case .lesson:
            await beginOrResumeLesson()
        case .freeForum:
            if let input = FreeFormInputStore.shared.consume(for: session.id) {
                await openingMessageWithFreeFormInput(text: input.text, images: input.images)
            }
        }
    }

    private func openingMessageWithFreeFormInput(text: String?, images: [UIImage]) async {
        let imageData = images.compactMap { $0.jpegData(compressionQuality: 0.72) }
        let imagePaths = saveImages(images, sessionId: session.id)
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmedText?.isEmpty == false) || !imageData.isEmpty else { return }

        let type: MessageType = imageData.isEmpty ? .text : (trimmedText?.isEmpty == false ? .mixed : .image)
        let userMsg = LocalChatMessage(
            sessionId: session.id,
            sender: .user,
            type: type,
            textContent: trimmedText?.isEmpty == false ? trimmedText : nil,
            imageLocalPaths: imagePaths
        )
        addMessage(userMsg)

        await generateAssistantReply(userText: trimmedText?.isEmpty == false ? trimmedText : nil, imageData: imageData)
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
        guard session.modeEnum != .lesson else {
            await generateLessonReply(userText: userText)
            return
        }
        guard session.modeEnum != .freeForum else {
            await generateFreeFormReply(userText: userText, imageData: imageData)
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
        case .lesson:
            systemPrompt = "" // unreachable — handled by the guard above
        case .freeForum:
            systemPrompt = "" // unreachable — handled by the guard above
        }

        let history = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
        let topic = session.sessionGoal ?? session.topic ?? "español general"
        let openingInstruction = PromptBuilder.openingSeedInstruction(profile: authState.profile, topic: topic)
        let userInput = userText ?? (imageData.isEmpty ? openingInstruction : "")

        do {
            var reply = try await openAI.sendMessage(
                systemPrompt: systemPrompt,
                history: history,
                userText: userInput,
                imageData: imageData,
                maxTokens: authState.profile?.effectiveStage.maxTokens ?? 300
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

    // MARK: - Say It Better (Lesson) — dock

    /// Builds `lessonState` once per session — regardless of whether this is
    /// a brand-new lesson session (no messages yet) or a resumed one — so the
    /// dock reflects whatever phase was persisted even when `openingMessage()`
    /// skips re-running the explain beat.
    private func setUpLessonStateIfNeeded() {
        guard session.modeEnum == .lesson, lessonState == nil,
              let lessonId = session.lessonId,
              let lesson = SayItBetterContentBank.shared.lesson(id: lessonId) else { return }

        let progress = existingLessonProgress(lessonId: lessonId)
            ?? {
                let created = LessonProgress(lessonId: lessonId, sessionId: session.id)
                modelContext.insert(created)
                try? modelContext.save()
                return created
            }()

        lessonState = LessonSessionState(lesson: lesson, progress: progress, modelContext: modelContext)
        // Covers the resumed-session case, where beginOrResumeLesson() won't
        // re-run (rootMessages isn't empty) but the save-to-memory affordance
        // still needs its message→phrase map rebuilt.
        lessonState?.linkExplanationMessages(rootMessages)

        // Fixes the gap beginOrResumeLesson()'s doc comment used to flag:
        // openingMessage() only (re)inserts a chapter's explanation and calls
        // markExplainDone() when rootMessages is empty, i.e. only on a
        // session's very first load. If that first pass is interrupted
        // (backgrounded, force-quit, backed out mid-autoplay) the messages
        // are already persisted, so on reopen rootMessages is non-empty,
        // beginOrResumeLesson() never re-runs, and the phase was stuck at
        // .explain forever — the Next Steps dock never appears and the
        // lesson becomes permanently stuck. Non-empty rootMessages at this
        // point can only mean the explanation was already (at least
        // partially) shown, so it's always safe to fast-forward the phase
        // rather than leave the learner with no way to proceed.
        if lessonState?.currentPhase == .explain, !rootMessages.isEmpty {
            lessonState?.markExplainDone()
        }
    }

    private func existingLessonProgress(lessonId: String) -> LessonProgress? {
        let descriptor = FetchDescriptor<LessonProgress>(
            predicate: #Predicate { $0.lessonId == lessonId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @ViewBuilder
    private func nextStepsDock(for state: LessonSessionState) -> some View {
        if state.currentPhase == .beforePracticeCheckpoint {
            NextStepsDockView(
                primaryLabel: L("Start practice"),
                secondaryLabel: L("Skip to lesson 2"),
                onPrimary: { practiceSession = state.buildPracticeSession() },
                onSecondary: { state.skipToNextChapter() }
            )
        } else if state.currentPhase == .practice {
            // Reached only when a prior attempt was interrupted (app
            // backgrounded/force-quit mid-quiz) — `recordPracticeResult()`
            // is the only other place that moves the phase off `.practice`,
            // so landing here always means there's a resumable position.
            NextStepsDockView(
                primaryLabel: L("Continue the quiz"),
                secondaryLabel: L("Restart the quiz"),
                onPrimary: { practiceSession = state.resumePracticeSession() },
                onSecondary: { practiceSession = state.buildPracticeSession() }
            )
        } else if state.practiceWasWeak {
            // Weak result (fewer than half correct): "Retake the quiz" reads
            // as the recommended action instead of "Next chapter" — same two
            // actions, swapped emphasis, not a third button.
            NextStepsDockView(
                primaryLabel: L("Retake the quiz"),
                secondaryLabel: L("Next chapter anyway"),
                onPrimary: { practiceSession = state.buildPracticeSession() },
                onSecondary: { state.skipToNextChapter() },
                tertiaryLabel: L("Listen to this chapter again"),
                onTertiary: { replayChapterExplanation(state) }
            )
        } else {
            NextStepsDockView(
                primaryLabel: L("Next chapter"),
                secondaryLabel: L("Retake the quiz"),
                onPrimary: { state.skipToNextChapter() },
                onSecondary: { practiceSession = state.buildPracticeSession() },
                tertiaryLabel: L("Listen to this chapter again"),
                onTertiary: { replayChapterExplanation(state) }
            )
        }
    }

    /// Replays the current chapter's already-inserted explanation bubbles
    /// from the start — no new messages, just audio, reusing the same
    /// pre-warmed-cache guarantee as the original autoplay (see
    /// beginOrResumeLesson). A natural "review before retaking" step,
    /// distinct from and lower-emphasis than the two real decisions above.
    private func replayChapterExplanation(_ state: LessonSessionState) {
        guard let firstId = state.firstExplanationMessageId else { return }
        TTSService.shared.speakQueue(
            startingFrom: firstId,
            in: state.explanationMessages,
            context: "sentence",
            allowOpenAIFallback: false
        )
    }

    // MARK: - Say It Better (Lesson)
    // beginOrResumeLesson() inserts chapter 1's explanation chunks as plain
    // text bubbles and autoplays them back-to-back via the same
    // TTSService.speakTurn queue Roleplay uses for its generated turns —
    // reused completely unmodified, since it's fully decoupled from how the
    // underlying messages were created. This still hits live TTS (fine for
    // dev iteration; must not ship this way — Phase 8 pre-warms the voice
    // cache so it's always a cache hit before any real user sees this).
    // Phase 4+ adds the Next Steps dock/practice-phase resume logic on top of
    // this. generateLessonReply will grow into the grounded before/after-
    // practice free-form Q&A path (Phase 4/6), using
    // PromptBuilder.lessonModePrompt instead of the topic/roleplay system
    // prompts.
    // `openingMessage()` only calls this when `rootMessages` is empty, so a
    // user who backs out mid-autoplay (or gets backgrounded/killed) and
    // returns will see the partial explanation with the phase still stuck at
    // `.explain` — nothing here re-inserts or advances it. That's fine
    // because `setUpLessonStateIfNeeded()` runs on every load, resumed or
    // not, and fast-forwards a stuck `.explain` phase to
    // `.beforePracticeCheckpoint` whenever messages already exist, so the
    // dock still shows up on the next load even if this exact autoplay pass
    // never finishes.
    private func beginOrResumeLesson() async {
        guard let state = lessonState, let chapter = state.currentChapter else {
            assertionFailure("No Say It Better lesson content found for session.lessonId")
            return
        }

        let language = LocalizationManager.shared.language
        var turnItems: [(id: UUID, text: String, voice: (languageCode: String, voiceName: String)?)] = []
        for chunk in chapter.explanation {
            let text = chunk.text(for: language)
            let msg = LocalChatMessage(
                sessionId: session.id,
                sender: .assistant,
                type: .text,
                textContent: text
            )
            addMessage(msg)
            turnItems.append((id: msg.id, text: text, voice: nil))
        }

        if autoVoiceEnabled, !turnItems.isEmpty {
            // "sentence" — not a custom "lesson" tag — deliberately: the server's
            // context allowlist doesn't include "lesson" (an unrecognized value
            // silently coerces to "default" server-side), and "sentence" already
            // gets exactly the right treatment for narrated multi-sentence
            // content (sentence-boundary pauses). Reusing it avoids a server
            // change and keeps the pre-warm script's cache keys trivially
            // correct — see render-say-it-better-assets.js.
            //
            // allowOpenAIFallback: false — this content is pre-generated and
            // pre-warmed, so a real request should always hit the shared
            // cache before this flag even matters. If it ever doesn't (a
            // pre-warm gap, an evicted cache entry), a different voice
            // appearing mid-explanation is worse than that one clip staying
            // silent — the server logs this case loudly since it should be
            // rare enough to always be worth investigating, not a normal
            // runtime condition to paper over.
            TTSService.shared.speakTurn(turnItems, context: "sentence", allowOpenAIFallback: false)
        }

        state.linkExplanationMessages(rootMessages)
        state.markExplainDone()
    }

    /// The manual "add to memory queue" affordance — user-initiated, not an
    /// automatic side effect. Reuses the same server-side "loro" pipeline
    /// Parrot already uses (a throwaway `ParrotPhrase`, never persisted,
    /// purely to drive `ParrotService.generate`) rather than duplicating its
    /// audio-generation logic, so quality and the 7-segment shape match
    /// exactly. Checks dedup before generating anything, so re-tapping an
    /// already-saved phrase costs nothing.
    // Handles both cases with one path: a real typed question during a
    // checkpoint (userText != nil, routed here via generateAssistantReply's
    // guard), and the automatic after-practice feedback message (userText ==
    // nil, triggered right after the practice carousel closes — see the
    // practiceSession fullScreenCover closure). Both are "Madrid answers
    // grounded in this lesson," just with a different trigger; no turn
    // classifier needed since the Next Steps dock's buttons are what
    // disambiguate act-vs-ask, not this call.
    //
    // This is ordinary live-generated chat — unlike the pre-written
    // explanation script (which Phase 8 guarantees never touches OpenAI and
    // is never synthesized live), a feedback/Q&A reply is inherently dynamic
    // per user, so it can't be pre-generated ahead of time. It uses the same
    // TTSService.speak(...) path and the same default voice fallback
    // behavior every other live chat reply in the app already has — that's
    // an existing, app-wide behavior this feature doesn't change, not a new
    // gap specific to Say It Better.
    private func generateLessonReply(userText: String?) async {
        guard let state = lessonState, let chapter = state.currentChapter else { return }
        isGenerating = true
        errorMessage = nil

        let practiceResults: [(question: String, wasCorrect: Bool)]? = state.lastPracticeResult.map { result in
            result.answers.map { answer in
                let prompt = chapter.quiz.first(where: { $0.id == answer.questionId })?.prompt(for: LocalizationManager.shared.language) ?? answer.questionId
                return (question: prompt, wasCorrect: answer.wasCorrect)
            }
        }

        let systemPrompt = PromptBuilder.lessonModePrompt(
            profile: authState.profile,
            lessonTitle: state.lesson.title(for: LocalizationManager.shared.language),
            currentChapterSummary: chapterSummary(for: chapter),
            practiceResults: practiceResults
        )

        let history = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
        let input = userText ?? "Dame tu feedback sobre cómo me fue en la práctica que acabo de terminar."

        do {
            let reply = try await openAI.sendMessage(
                systemPrompt: systemPrompt,
                history: history,
                userText: input,
                imageData: [],
                maxTokens: authState.profile?.effectiveStage.maxTokens ?? 300
            )
            let assistantMsg = LocalChatMessage(
                sessionId: session.id,
                sender: .assistant,
                type: .text,
                textContent: reply
            )
            addMessage(assistantMsg)
            // userText == nil is exactly the auto-triggered post-practice
            // call (see the practiceSession fullScreenCover closure) — a
            // genuine typed question never reaches here with nil userText.
            if userText == nil {
                state.markFeedbackMessage(assistantMsg.id)
            }
            if autoVoiceEnabled && !TTSService.shared.isQueueActive {
                TTSService.shared.speak(text: reply, messageId: assistantMsg.id, context: "sentence")
            }

            ProfileAnalystService.shared.analyzeExchange(
                userMessage: rootMessages.last(where: { $0.isUser }),
                tutorMessage: assistantMsg,
                session: session,
                authState: authState
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    // MARK: - Ask in a Free Forum

    // Every message (opening or follow-up) is classified fresh — see
    // FreeFormScenarioClassifierService — since one session can drift
    // between scenarios (homework, then a plain question, then a
    // correctness check). Text-only mode throughout: no TTSService call
    // anywhere in this function, on purpose — see SessionMode.isTextOnly.
    private func generateFreeFormReply(userText: String?, imageData: [Data]) async {
        isGenerating = true
        errorMessage = nil

        let classifierHistory = Array(rootMessages.filter { $0.textContent != nil }.suffix(4))
        let scenario = await FreeFormScenarioClassifierService.shared.classify(
            userMessage: userText ?? "",
            hasImages: !imageData.isEmpty,
            recentHistory: classifierHistory
        )

        let firstSystemPrompt: String
        switch scenario {
        case .homeworkHelp: firstSystemPrompt = PromptBuilder.freeFormHomeworkHelpPrompt(profile: authState.profile)
        case .isItCorrect:  firstSystemPrompt = PromptBuilder.freeFormCorrectionPrompt(profile: authState.profile)
        case .explainMe:    firstSystemPrompt = PromptBuilder.freeFormExplainMePrompt(profile: authState.profile)
        }

        let history = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
        let input = userText ?? ""

        do {
            let firstReply = try await openAI.sendMessage(
                systemPrompt: firstSystemPrompt,
                history: history,
                userText: input,
                imageData: imageData,
                maxTokens: authState.profile?.effectiveStage.maxTokens ?? 300
            )
            let firstMsg = LocalChatMessage(
                sessionId: session.id,
                sender: .assistant,
                type: .text,
                textContent: firstReply
            )
            addMessage(firstMsg)

            var lastAssistantMsg = firstMsg
            if scenario == .isItCorrect {
                let explanationHistory = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
                let explanationInput = "Explica en detalle por qué esa versión es más correcta o más natural que lo que escribí originalmente."
                let explanation = try await openAI.sendMessage(
                    systemPrompt: PromptBuilder.freeFormExplanationPrompt(profile: authState.profile),
                    history: explanationHistory,
                    userText: explanationInput,
                    imageData: [],
                    maxTokens: authState.profile?.effectiveStage.maxTokens ?? 300
                )
                let explanationMsg = LocalChatMessage(
                    sessionId: session.id,
                    sender: .assistant,
                    type: .text,
                    textContent: explanation
                )
                addMessage(explanationMsg)
                lastAssistantMsg = explanationMsg
            }

            ProfileAnalystService.shared.analyzeExchange(
                userMessage: rootMessages.last(where: { $0.isUser }),
                tutorMessage: lastAssistantMsg,
                session: session,
                authState: authState
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    private func chapterSummary(for chapter: Chapter) -> String {
        chapter.items.map { item in
            "\"\(item.spanish)\" = \(item.englishMeaning) (\(item.registerNote)). Ejemplo: \(item.exampleSentence)"
        }.joined(separator: "\n")
    }

    // MARK: - Roleplay LLM

    // After every user message (or the opening instruction), a cheap
    // classifier call (RoleplayTurnClassifierService) decides who speaks
    // first, then who speaks next after EVERY subsequent AI message — Madrid,
    // the guest, or handing back to the student — capped at 3 AI messages in
    // a row. This replaces the old single-call "whole multi-line round"
    // design: there's no round boundary left for a cross-question to get
    // stranded at, since the classifier re-evaluates after each message.
    private static let maxAIMessagesPerRound = 3

    private func generateRoleplayReply(userText: String?, forcedFirstSpeaker: String? = nil) async {
        isGenerating = true
        errorMessage = nil

        let objectLabel = session.roleplayObjectLabel ?? "a mysterious guest"
        let environmentLabel = session.roleplayEnvironmentLabel ?? "a cozy studio"
        let topic = session.topic ?? "everyday life"
        let objectVoiceName = session.roleplayObjectVoice ?? RoleplayContent.voiceForObject(objectLabel)

        let openingInstruction = "Empieza el programa ya. Preséntate brevemente, presenta a tu invitado de hoy y deja que reaccione."
        let userInput = userText ?? openingInstruction
        // Each call now produces just one short spoken line instead of a
        // whole multi-line round, so it needs far less headroom than before.
        let roleplayMaxTokens = 160

        var turnItems: [(id: UUID, text: String, voice: (languageCode: String, voiceName: String)?)] = []
        var lastAddedMessage: LocalChatMessage?

        // The very first exchange of a session must establish that this is a
        // 3-way conversation, not just Madrid. Leaving that entirely to the
        // classifier meant it could (and did, in testing) hand straight back
        // to the student right after Madrid's opening line, before the guest
        // ever got a turn. So the opening is a guaranteed, hardcoded
        // sequence — Madrid introduces, then the guest reacts — and only from
        // the 3rd message onward (if the cap allows it) does the classifier
        // get a say, exactly like every other round.
        let isOpening = userText == nil

        do {
            var speaker: String
            if let forcedFirstSpeaker {
                // The student explicitly chose who speaks next (a "pass the
                // word" tap) — no need to ask the classifier to infer that
                // from the canned line's wording.
                speaker = forcedFirstSpeaker
            } else if isOpening {
                speaker = "madrid"
            } else {
                let initialHistory = Array(rootMessages.filter { $0.textContent != nil }.suffix(4))
                speaker = await RoleplayTurnClassifierService.shared.classifyNextSpeaker(
                    recentHistory: initialHistory,
                    objectLabel: objectLabel,
                    allowHandToUser: false
                )
            }

            var aiTurnsThisRound = 0
            var isFirstGeneration = true

            while aiTurnsThisRound < Self.maxAIMessagesPerRound {
                let systemPrompt = PromptBuilder.roleplaySinglespeakerPrompt(
                    profile: authState.profile,
                    objectLabel: objectLabel,
                    environmentLabel: environmentLabel,
                    topic: topic,
                    speaker: speaker
                )
                let currentHistory = Array(rootMessages.filter { $0.textContent != nil }.suffix(20))
                let generationInput = isFirstGeneration ? userInput : "Sigue tú — continúa el programa con tu siguiente línea, en tu papel."

                let raw = try await ProxyClient.shared.chatRoleplay(
                    systemPrompt: systemPrompt,
                    history: currentHistory,
                    userText: generationInput,
                    maxTokens: roleplayMaxTokens,
                    // Only the first generation call of the round is billed —
                    // every continuation within the same user-triggered round
                    // is a free follow-up, same flat charge as before.
                    isRetry: !isFirstGeneration
                )
                isFirstGeneration = false

                let text = stripLeakedSpeakerLabel(
                    raw.trimmingCharacters(in: .whitespacesAndNewlines),
                    objectLabel: objectLabel
                )
                guard !text.isEmpty else { break }

                let msg = LocalChatMessage(
                    sessionId: session.id,
                    sender: .assistant,
                    type: .text,
                    textContent: text,
                    speakerId: speaker
                )
                addMessage(msg)
                lastAddedMessage = msg

                let voice: (languageCode: String, voiceName: String)? =
                    speaker == "object" ? (languageCode: "es-ES", voiceName: objectVoiceName) : nil
                turnItems.append((id: msg.id, text: text, voice: voice))

                aiTurnsThisRound += 1
                if aiTurnsThisRound >= Self.maxAIMessagesPerRound { break }

                if isOpening && aiTurnsThisRound == 1 {
                    // Second forced beat: the guest reacts to Madrid's intro,
                    // no classifier involved yet.
                    speaker = "object"
                    continue
                }

                let nextHistory = Array(rootMessages.filter { $0.textContent != nil }.suffix(4))
                let next = await RoleplayTurnClassifierService.shared.classifyNextSpeaker(
                    recentHistory: nextHistory,
                    objectLabel: objectLabel,
                    allowHandToUser: true
                )
                if next == "user" { break }
                speaker = next
            }

            if autoVoiceEnabled, !turnItems.isEmpty {
                TTSService.shared.speakTurn(turnItems)
            }

            if let lastAddedMessage {
                ProfileAnalystService.shared.analyzeExchange(
                    userMessage: rootMessages.last(where: { $0.isUser }),
                    tutorMessage: lastAddedMessage,
                    session: session,
                    authState: authState
                )
            }

            refreshSuggestedReplies(objectLabel: objectLabel, topic: topic)
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    // Defensive cleanup: even though the single-speaker prompt says "no tags,
    // no labels, no name prefix", the model sometimes imitates whatever
    // speaker-tagging shape appears in the fed history (confirmed by direct
    // simulation, across two different history-tagging formats) and prefixes
    // its own new line with something like "[MADRID] ..." or "Madrid: ...".
    // Strip a leaking leading label deterministically rather than chasing
    // prompt wording further.
    private func stripLeakedSpeakerLabel(_ text: String, objectLabel: String) -> String {
        let escapedObject = NSRegularExpression.escapedPattern(for: objectLabel)
        let pattern = "^\\[?(?:MADRID|OBJECT|Madrid|\(escapedObject))\\]?:?\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
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
