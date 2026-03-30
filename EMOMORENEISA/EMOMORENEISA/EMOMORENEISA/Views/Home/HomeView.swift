import SwiftUI

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

            if case .countdown(let n) = engine.phase {
                CountdownOverlayView(count: n)
                    .transition(.opacity)
                    .zIndex(100)
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
