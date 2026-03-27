import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var engine: GameEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    scoreHeader

                    if let round = engine.round, !round.correctCells.isEmpty {
                        cellSection(
                            title: "CORRECT",
                            cells: round.correctCells,
                            color: .green
                        )
                    }

                    if let round = engine.round, !round.missedCells.isEmpty {
                        cellSection(
                            title: "MISSED",
                            cells: round.missedCells,
                            color: .red
                        )
                    }

                    actionButtons
                }
                .padding(20)
            }
        }
    }

    private var scoreHeader: some View {
        VStack(spacing: 8) {
            Text("ROUND COMPLETE")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .tracking(2)

            let correct = engine.round?.correctCells.count ?? 0
            let total = engine.round?.cells.count ?? 0

            Text("\(correct) / \(total)")
                .font(.system(size: 64, weight: .black, design: .monospaced))
                .foregroundColor(correct == total ? .green : .yellow)
                .shadow(color: (correct == total ? Color.green : Color.yellow).opacity(0.6), radius: 12)

            Text(correct == total ? "PERFECT" : "\(total - correct) TO REVIEW")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(correct == total ? .green.opacity(0.7) : .white.opacity(0.4))
                .tracking(1)
        }
    }

    private func cellSection(title: String, cells: [GameCell], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .tracking(2)
                .shadow(color: color.opacity(0.5), radius: 4)
                .padding(.horizontal, 4)

            ForEach(cells) { cell in
                HStack {
                    Text(cell.pronoun.displayLabel)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 90, alignment: .leading)

                    Text(cell.verb.infinitive)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(cell.expectedConjugation)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .shadow(color: color.opacity(0.4), radius: 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            if let round = engine.round, !round.missedCells.isEmpty {
                Button {
                    engine.retryMissed()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("RETRY MISSED (\(engine.round?.missedCells.count ?? 0))")
                    }
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                engine.newRound()
            } label: {
                Text("NEW ROUND")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
