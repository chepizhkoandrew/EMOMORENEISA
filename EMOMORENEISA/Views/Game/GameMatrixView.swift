import SwiftUI

struct GameMatrixView: View {
    @EnvironmentObject var engine: GameEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                headerRow
                Divider().background(Color.white.opacity(0.2))
                matrixBody
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)

            if engine.isListening {
                listeningIndicator
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("")
                .frame(width: 80)

            ForEach(Array(engine.selectedVerbs.enumerated()), id: \.offset) { _, verb in
                VStack(spacing: 2) {
                    Text(verb.infinitive)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                    if verb.joker {
                        Text(verb.jokerKind == .fullyIrregular ? "irreg." : "stem")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                    } else {
                        Text("-\(verb.type.rawValue)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }

    private var matrixBody: some View {
        VStack(spacing: 6) {
            ForEach(Pronoun.allCases) { pronoun in
                HStack(spacing: 6) {
                    Text(pronoun.displayLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    ForEach(engine.selectedVerbs) { verb in
                        if let cell = cell(pronoun: pronoun, verb: verb) {
                            MatrixCellView(
                                cell: cell,
                                isActive: isCellActive(cell),
                                timerProgress: isCellActive(cell) ? timerProgress : 1.0,
                                showAnswerHint: engine.showAnswerHint
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var listeningIndicator: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.8)
                Text("Listening...")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .padding(.bottom, 32)
        }
    }

    private func cell(pronoun: Pronoun, verb: Verb) -> GameCell? {
        engine.round?.cells.first { $0.pronoun == pronoun && $0.verb.infinitive == verb.infinitive }
    }

    private func isCellActive(_ cell: GameCell) -> Bool {
        guard let active = engine.activeCell else { return false }
        return active.id == cell.id
    }

    private var timerProgress: Double {
        engine.timeRemaining / engine.timerSeconds
    }
}
