import SwiftUI
import SwiftData

// 3-step setup wizard for the Roleplay podcast feature: pick who you're
// talking to (an object/character), where it happens, and what it's about —
// then generate a scene background and hand off to ChatView, same contract
// as NewSessionView's onSessionCreated.
struct RoleplaySetupView: View {
    let onSessionCreated: (LocalChatSession) -> Void
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Step { case object, environment, topic }

    @State private var step: Step = .object
    @State private var objectText: String = ""
    @State private var environmentText: String = ""
    @State private var topicText: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String? = nil
    @State private var creationStartedAt: Date? = nil

    // Scene generation alone measured ~8-9s against the real Vertex/Gemini
    // pipeline (see server-side verification notes) — this is a fixed guess
    // for pacing the progress bar, not a real ETA from the server, since
    // fetchRoleplayScene is a single blocking call, not a polled job like
    // song generation.
    private let creationEtaSeconds: Double = 10
    private let creationStages: [(threshold: Double, text: String)] = [
        (0.0, "Setting the scene…"),
        (0.35, "Getting your guest ready…"),
        (0.7, "Rehearsing the opening lines…"),
        (0.92, "Almost ready…")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Group {
                    if isCreating {
                        workingCard
                    } else {
                        switch step {
                        case .object:      pickerContent(
                            prompt: L("Who do you want to talk to?"),
                            placeholder: L("e.g. \"Cleopatra\"…"),
                            options: RoleplayContent.objects,
                            text: $objectText,
                            buttonTitle: L("Next"),
                            action: { step = .environment }
                        )
                        case .environment: pickerContent(
                            prompt: L("Where does this happen?"),
                            placeholder: L("e.g. \"a rooftop terrace at sunset\"…"),
                            options: RoleplayContent.environments,
                            text: $environmentText,
                            buttonTitle: L("Next"),
                            action: { step = .topic }
                        )
                        case .topic: pickerContent(
                            prompt: L("What are they talking about?"),
                            placeholder: L("e.g. \"travel dreams\"…"),
                            options: RoleplayContent.topics,
                            text: $topicText,
                            buttonTitle: L("Start the Show"),
                            action: startRoleplay
                        )
                        }
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
                    BackButton { stepBackOrDismiss() }
                }
            }
        }
    }

    private var navTitle: String {
        switch step {
        case .object:      return L("Your Guest")
        case .environment: return L("The Setting")
        case .topic:       return L("The Topic")
        }
    }

    private func stepBackOrDismiss() {
        switch step {
        case .object:      dismiss()
        case .environment: step = .object
        case .topic:       step = .environment
        }
    }

    // MARK: - Shared step content

    @ViewBuilder
    private func pickerContent(
        prompt: String,
        placeholder: String,
        options: [String],
        text: Binding<String>,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    Text(prompt)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    freeTextField(placeholder: placeholder, text: text)

                    optionsSection(options: options, text: text)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
            }

            bottomBar(title: buttonTitle, disabled: text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, action: action)
        }
    }

    private func freeTextField(placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextField("", text: text, axis: .vertical)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1...3)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
        }
        .background(AppColors.inputBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.inputBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func optionsSection(options: [String], text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Quick picks"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            FlowLayout(hSpacing: 10, vSpacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button(action: { text.wrappedValue = option }) {
                        Text(L(option))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(text.wrappedValue == option ? .black : AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(text.wrappedValue == option ? Color.yellow : AppColors.inputBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(text.wrappedValue == option ? Color.yellow : AppColors.inputBorder, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: text.wrappedValue == option)
                }
            }
        }
    }

    private func bottomBar(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

    // MARK: - Loading Card

    private var workingCard: some View {
        TimelineView(.animation) { context in
            let startedAt = creationStartedAt ?? context.date
            let elapsed = context.date.timeIntervalSince(startedAt)
            let fraction = min(0.97, elapsed / creationEtaSeconds)
            let stageText = creationStages.last(where: { fraction >= $0.threshold })?.text ?? creationStages[0].text

            VStack(spacing: 18) {
                Text(L(stageText))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: stageText)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.yellow)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 8)

                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Session Creation

    private func startRoleplay() {
        guard let userId = authState.userId else { return }
        let objectLabel = objectText.trimmingCharacters(in: .whitespaces)
        let environmentLabel = environmentText.trimmingCharacters(in: .whitespaces)
        let topicLabel = topicText.trimmingCharacters(in: .whitespaces)
        guard !objectLabel.isEmpty, !environmentLabel.isEmpty, !topicLabel.isEmpty else { return }

        isCreating = true
        creationStartedAt = Date()
        errorMessage = nil
        let voiceName = RoleplayContent.voiceForObject(objectLabel)
        let sessionId = UUID()

        Task {
            var scenePath: String? = nil
            if let (data, _) = await ProxyClient.shared.fetchRoleplayScene(objectLabel: objectLabel, environmentLabel: environmentLabel) {
                scenePath = saveSceneImage(data, sessionId: sessionId)
            }

            await MainActor.run {
                let session = LocalChatSession(
                    id: sessionId,
                    userId: userId,
                    mode: .roleplay,
                    title: "\(objectLabel.capitalized(with: nil)) — \(topicLabel.capitalized(with: nil))",
                    topic: topicLabel,
                    roleplayObjectLabel: objectLabel,
                    roleplayEnvironmentLabel: environmentLabel,
                    roleplayObjectVoice: voiceName,
                    roleplaySceneImagePath: scenePath
                )
                modelContext.insert(session)
                try? modelContext.save()
                Task {
                    await SupabaseSyncService.shared.upsertSession(session, userId: userId)
                }
                AnalyticsService.shared.track(.sessionCreated(mode: SessionMode.roleplay.rawValue))
                isCreating = false
                onSessionCreated(session)
            }
        }
    }

    private func saveSceneImage(_ data: Data, sessionId: UUID) -> String {
        let relativeDir = "esp-images/\(sessionId.uuidString)"
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docsDir.appendingPathComponent(relativeDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("scene.jpg")
        try? data.write(to: url)
        return relativeDir + "/scene.jpg"
    }
}
