import SwiftUI

struct HomeView: View {
    @StateObject private var engine = GameEngine()
    @State private var timerSeconds: Double = 4.0
    @State private var selectedTense: Tense = .present
    @State private var speechPermissionGranted = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch engine.phase {
            case .idle:
                TypewriterIntroView(
                    onContinue: {
                        engine.timerSeconds = timerSeconds
                        engine.selectedTense = selectedTense
                        engine.startSpin()
                    },
                    timerSeconds: $timerSeconds,
                    selectedTense: $selectedTense
                )
                .transition(.opacity)

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
        }
        .animation(.easeInOut(duration: 0.35), value: engine.phase == .idle)
        .onAppear {
            SpeechService().requestPermission { granted in
                speechPermissionGranted = granted
            }
        }
    }
}
