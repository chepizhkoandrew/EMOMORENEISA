import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var engine: GameEngine
    @State private var appear = false
    @AppStorage("stats.verbGamesPlayed") private var verbGamesPlayed: Int = 0

    private var correct: Int { engine.round?.correctCells.count ?? 0 }
    private var total: Int { engine.round?.cells.count ?? 0 }
    private var isPerfect: Bool { correct == total && total > 0 }

    var body: some View {
        ZStack {
            GameBackground()

            if isPerfect {
                ConfettiView()
            }

            ScrollView {
                VStack(spacing: 28) {
                    scoreHeader
                        .padding(.top, 16)
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : -20)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.05), value: appear)

                    if let round = engine.round, !round.correctCells.isEmpty {
                        cellSection(
                            title: L("CORRECT"),
                            emoji: "✓",
                            cells: round.correctCells,
                            color: GameColors.verde,
                            gradient: GameColors.correctGradient,
                            isCorrect: true
                        )
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15), value: appear)
                    }

                    if let round = engine.round, !round.missedCells.isEmpty {
                        cellSection(
                            title: L("MISSED"),
                            emoji: "✗",
                            cells: round.missedCells,
                            color: GameColors.rojo,
                            gradient: GameColors.missedGradient,
                            isCorrect: false
                        )
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.25), value: appear)
                    }

                    actionButtons
                        .opacity(appear ? 1 : 0)
                        .offset(y: appear ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.35), value: appear)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            appear = true
            verbGamesPlayed += 1
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(spacing: 12) {
            Text(isPerfect ? "🏆" : correct > total / 2 ? "🥈" : "💪")
                .font(.system(size: 72))
                .shadow(color: isPerfect ? Color.yellow.opacity(0.6) : .clear, radius: 20)

            Text(isPerfect ? L("PERFECT ROUND!") : L("ROUND COMPLETE"))
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(isPerfect ? GameColors.gold : .white.opacity(0.55))
                .tracking(3)
                .shadow(color: isPerfect ? GameColors.gold.opacity(0.5) : .clear, radius: 8)

            Text("\(correct) / \(total)")
                .font(.system(size: 80, weight: .black, design: .monospaced))
                .foregroundColor(isPerfect ? GameColors.gold : GameColors.verde)
                .shadow(color: (isPerfect ? GameColors.gold : GameColors.verde).opacity(0.55), radius: 16)

            Text(isPerfect ? L("¡Excelente! All conjugations correct") : L("%d to review", total - correct))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(isPerfect ? GameColors.verde.opacity(0.80) : .white.opacity(0.45))
                .tracking(1)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Cell Section

    private func cellSection(
        title: String,
        emoji: String,
        cells: [GameCell],
        color: Color,
        gradient: LinearGradient,
        isCorrect: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(color)
                    .tracking(3)
                    .shadow(color: color.opacity(0.5), radius: 4)
                Spacer()
                Text("\(cells.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(color.opacity(0.60))
            }
            .padding(.horizontal, 2)

            ForEach(cells) { cell in
                HStack(spacing: 12) {
                    Text(cell.pronoun.displayLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(color.opacity(0.65))
                        .frame(width: 100, alignment: .leading)

                    Text(cell.verb.infinitive)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.60))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        Image(systemName: isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(color)
                        Text(cell.expectedConjugation)
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(color)
                            .shadow(color: color.opacity(0.45), radius: 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let round = engine.round, !round.missedCells.isEmpty {
                Button {
                    engine.retryMissed()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                        Text(L("RETRY MISSED (%d)", engine.round?.missedCells.count ?? 0))
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(GameColors.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: GameColors.gold.opacity(0.50), radius: 12, y: 4)
                }
            }

            Button {
                engine.newRound()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("NEW ROUND"))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.80))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.white.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
