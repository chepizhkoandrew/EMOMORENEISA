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
                            title: "Correct",
                            cells: round.correctCells,
                            color: .green
                        )
                    }

                    if let round = engine.round, !round.missedCells.isEmpty {
                        cellSection(
                            title: "Missed",
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
            Text("Round Complete")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)

            let correct = engine.round?.correctCells.count ?? 0
            let total = engine.round?.cells.count ?? 0

            Text("\(correct) / \(total)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(correct == total ? .green : .yellow)

            Text(correct == total ? "Perfect!" : "\(total - correct) to review")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
        }
    }

    private func cellSection(title: String, cells: [GameCell], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .padding(.horizontal, 4)

            ForEach(cells) { cell in
                HStack {
                    Text(cell.pronoun.displayLabel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                        .frame(width: 90, alignment: .leading)

                    Text(cell.verb.infinitive)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(cell.expectedConjugation)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(color.opacity(0.1))
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
                    Label("Retry Missed (\(engine.round?.missedCells.count ?? 0))", systemImage: "arrow.clockwise")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                engine.newRound()
            } label: {
                Text("New Round")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
