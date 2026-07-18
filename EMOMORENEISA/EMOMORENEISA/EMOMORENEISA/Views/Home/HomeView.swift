import SwiftUI
import SwiftData

struct CountdownOverlayView: View {
    let count: Int
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0.9

    private var accent: Color {
        switch count {
        case 3: return .red
        case 2: return .orange
        case 1: return .green
        default: return .yellow
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(accent.opacity(max(0, ringOpacity - Double(i) * 0.28)), lineWidth: 2.5)
                        .frame(width: 170, height: 170)
                        .scaleEffect(ringScale + CGFloat(i) * 0.35)
                }

                Text("\(count)")
                    .font(.system(size: 150, weight: .black, design: .monospaced))
                    .foregroundColor(accent)
                    .shadow(color: accent.opacity(0.95), radius: 24)
                    .shadow(color: accent.opacity(0.4), radius: 56)
                    .scaleEffect(scale)
                    .opacity(opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.48)) {
                scale = 1.0
                opacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.85)) {
                ringScale = 2.4
                ringOpacity = 0
            }
        }
        .id(count)
    }
}

struct HomeView: View {
    @StateObject private var engine = GameEngine()
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("timerSeconds") private var timerSeconds: Double = 4.0
    @AppStorage("selectedTenseName") private var selectedTenseName: String = Tense.present.rawValue
    @State private var speechPermissionGranted = false
    @State private var showModeSelector: Bool = false
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            AppBackground()

            switch engine.phase {
            case .idle:
                if authState.isLoading {
                    // Session restore races first paint — show nothing until it
                    // resolves so an already-signed-in user never sees a flash
                    // of SignInView before we know they're authenticated.
                    ProgressView()
                        .tint(.yellow)
                        .scaleEffect(1.4)
                        .transition(.opacity)
                } else if !authState.isSignedIn {
                    // Sign-in is the very first screen — no game mode is
                    // reachable without an account.
                    SignInView()
                        .environment(authState)
                        .transition(.opacity)
                } else if authState.needsAIDisclosure {
                    // Blocks EVERYTHING past this point, including the
                    // onboarding voice quiz — that quiz itself sends
                    // recordings to Gemini, so the disclosure must come
                    // first. Applies to existing accounts too, not just new
                    // signups (see AuthState.needsAIDisclosure).
                    AIDisclosureView()
                        .transition(.opacity)
                } else if showModeSelector || !authState.needsOnboarding {
                    // Returning user who already finished the tour + voice
                    // quiz (or someone who progressed there already this
                    // session) — skip straight past the typewriter/carousel.
                    // No extra audio setup needed here: the `.onAppear`/
                    // `.onChange` below already start background music
                    // unconditionally before this switch ever branches.
                    ModeSelectorView(onVerbGame: { tense in
                        engine.timerSeconds = timerSeconds
                        engine.selectedTense = tense
                        selectedTenseName = tense.rawValue
                        engine.startSpin()
                    })
                    .environment(authState)
                    .transition(.opacity)
                    .task { await WalletManager.shared.bootstrap() }
                } else if showOnboarding {
                    OnboardingCarouselView(
                        onFinish: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                showModeSelector = true
                            }
                        }
                    )
                    .transition(.opacity)
                } else {
                    TypewriterIntroView(
                        onContinue: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showOnboarding = true
                            }
                        }
                    )
                    .transition(.opacity)
                }

            case .spinning, .readyToStart, .countdown:
                SlotMachineView()
                    .environmentObject(engine)
                    .transition(.opacity)

            case .playing, .review:
                GameMatrixView()
                    .environmentObject(engine)
                    .transition(.opacity)

            case .results:
                ResultsView()
                    .environmentObject(engine)
                    .transition(.opacity)
            }

            if case .countdown(let n) = engine.phase {
                CountdownOverlayView(count: n)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: engine.phase == .idle)
        .onAppear {
            engine.attemptService = VerbAttemptService(context: modelContext)
            SpeechService().requestPermission { granted in
                speechPermissionGranted = granted
            }
            BackgroundMusicPlayer.shared.play()
        }
        .onChange(of: engine.phase) { _, newPhase in
            switch newPhase {
            case .idle:
                BackgroundMusicPlayer.shared.play()
            case .spinning, .readyToStart:
                BackgroundMusicPlayer.shared.fadeOut(duration: 0.8)
                TTSService.shared.stop()
                OnboardAudioManager.shared.stop()
            case .countdown, .playing, .review, .results:
                BackgroundMusicPlayer.shared.fadeOut(duration: 1.5)
            }
        }
        .onChange(of: authState.userId) { _, _ in
            // HomeView is a single long-lived instance — these @State flags
            // otherwise never reset within a running process. Without this,
            // a sign-out/sign-in (or switching accounts) inherits whatever
            // showModeSelector was left at by the PREVIOUS session, which
            // short-circuits the `!authState.needsOnboarding` check below
            // and silently skips onboarding even when the fresh profile says
            // it's needed (only a full process relaunch happened to reset
            // this by accident before, masking the bug).
            showModeSelector = false
            showOnboarding = false
        }
    }
}
