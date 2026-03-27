import SwiftUI

struct HomeView: View {
    @StateObject private var engine = GameEngine()
    @State private var timerSeconds: Double = 2.0
    @State private var selectedTense: Tense = .present
    @State private var speechPermissionGranted = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch engine.phase {
            case .idle:
                homeContent

            case .spinning, .readyToStart, .countdown:
                SlotMachineView()
                    .environmentObject(engine)
                    .transition(.opacity)

            case .playing:
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

    private var homeContent: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 8) {
                Text("EMOMORENEISA")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                    .tracking(4)

                Text("Spanish Verb Trainer")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Tense", systemImage: "book.closed.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.gray)

                    Picker("Tense", selection: $selectedTense) {
                        ForEach(Tense.allCases) { tense in
                            Text(tense.displayLabel).tag(tense)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorMultiply(.yellow)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Timer per word", systemImage: "timer")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.1fs", timerSeconds))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }

                    Slider(value: $timerSeconds, in: 1.0...8.0, step: 0.5)
                        .accentColor(.yellow)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 24)

            if !speechPermissionGranted {
                Text("Microphone & speech access required")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
            }

            Button {
                engine.timerSeconds = timerSeconds
                engine.selectedTense = selectedTense
                engine.startSpin()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("Start Round")
                }
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(speechPermissionGranted ? Color.yellow : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            }
            .disabled(!speechPermissionGranted)

            Spacer()
        }
    }
}
