import SwiftUI

struct SlotMachineView: View {
    @EnvironmentObject var engine: GameEngine

    @State private var stoppedCount = 0
    private let allInfinitives: [String] = VerbDatabase.shared.all.map(\.infinitive)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("EMOMORENEISA")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                    .tracking(4)

                HStack(spacing: 12) {
                    ForEach(Array(engine.selectedVerbs.enumerated()), id: \.offset) { index, verb in
                        SpinningWheelView(
                            items: allInfinitives,
                            finalItem: verb.infinitive,
                            delay: Double(index) * 0.6
                        ) {
                            stoppedCount += 1
                            if stoppedCount == engine.selectedVerbs.count {
                                engine.onSpinComplete()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)

                if engine.phase == .readyToStart {
                    Button {
                        engine.beginCountdown()
                    } label: {
                        Text("TAP TO START")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                            .background(Color.yellow)
                            .clipShape(Capsule())
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                if case .countdown(let n) = engine.phase {
                    Text("\(n)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                        .transition(.scale.combined(with: .opacity))
                        .id(n)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: engine.phase == .readyToStart)
    }
}
