import SwiftUI
import SwiftData

struct ThreadSheetView: View {
    let session: LocalChatSession
    let parentMessage: LocalChatMessage
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String? = nil
    @AppStorage("autoVoiceEnabled") private var autoVoiceEnabled: Bool = true

    private let openAI = ChatOpenAIService()

    private var threadMessages: [LocalChatMessage] {
        session.messages
            .filter { $0.threadParentId == parentMessage.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    parentHeader
                    Divider().background(AppColors.cardBorder)
                    threadMessageList
                    threadInputBar
                }
            }
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.yellow)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    private var parentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Original message")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
                .tracking(1)
            if let text = parentMessage.textContent {
                Text(text)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
    }

    private var threadMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(threadMessages) { message in
                        MessageBubbleView(
                            message: message,
                            onReplyInThread: {},
                            onPlayFromHere: {
                                let items = threadMessages
                                    .compactMap { m -> (id: UUID, text: String)? in
                                        guard let t = m.textContent, !t.isEmpty else { return nil }
                                        return (id: m.id, text: t)
                                    }
                                TTSService.shared.toggleQueue(startingFrom: message.id, in: items)
                            },
                            onParrot: {}
                        )
                        .id(message.id)
                    }
                    if isGenerating {
                        ProgressView().tint(.yellow).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                    }
                    Color.clear.frame(height: 8).id("threadBottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: threadMessages.count) { _, _ in
                withAnimation { proxy.scrollTo("threadBottom") }
            }
        }
    }

    private var threadInputBar: some View {
        HStack(spacing: 12) {
            TextField("Reply in thread…", text: $inputText, axis: .vertical)
                .font(.system(size: 17, design: .monospaced))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppColors.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppColors.inputBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 22))

            Button(action: sendReply) {
                Image(systemName: isGenerating ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating ? AppColors.textTertiary : .yellow)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.backgroundTop)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(AppColors.cardBorder), alignment: .top)
    }

    private func sendReply() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""

        let msg = LocalChatMessage(
            sessionId: session.id,
            threadParentId: parentMessage.id,
            sender: .user,
            type: .text,
            textContent: text
        )
        addThreadMessage(msg)
        Task { await generateThreadReply(userText: text) }
    }

    private func generateThreadReply(userText: String) async {
        isGenerating = true
        let systemPrompt = PromptBuilder.topicSystemPrompt(profile: authState.profile, topic: session.topic)
        var context: [LocalChatMessage] = []
        if parentMessage.textContent != nil { context.append(parentMessage) }
        context.append(contentsOf: threadMessages)

        do {
            let reply = try await openAI.sendMessage(
                systemPrompt: systemPrompt,
                history: context,
                userText: userText
            )
            let assistantMsg = LocalChatMessage(
                sessionId: session.id,
                threadParentId: parentMessage.id,
                sender: .assistant,
                type: .text,
                textContent: reply
            )
            addThreadMessage(assistantMsg)
            if autoVoiceEnabled && !TTSService.shared.isQueueActive {
                TTSService.shared.speak(text: reply, messageId: assistantMsg.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    private func addThreadMessage(_ message: LocalChatMessage) {
        modelContext.insert(message)
        session.messages.append(message)
        parentMessage.threadReplyCount = threadMessages.count + 1
        try? modelContext.save()
        Task { await SupabaseSyncService.shared.insertMessage(message) }
    }
}
