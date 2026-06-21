import SwiftUI

struct MatrixCellView: View {
    let cell: GameCell
    let isActive: Bool
    let timerProgress: Double
    @AppStorage("showAnswerHint") private var showAnswerHint: Bool = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            cellBackground

            if isActive {
                TimerArcView(progress: timerProgress)
                    .padding(3)
            }

            if isActive && showAnswerHint {
                Text(cell.expectedConjugation)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(6)
            } else if cell.revealed {
                revealedContent
            } else {
                Image(systemName: isActive ? "mic.fill" : "questionmark")
                    .font(.system(size: isActive ? 24 : 20, weight: .semibold))
                    .foregroundColor(isActive ? .yellow : .white.opacity(0.25))
                    .shadow(color: isActive ? Color.yellow.opacity(0.7) : .clear, radius: 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: isActive ? 2 : 1)
        )
        .scaleEffect(isActive ? (breathe ? 1.06 : 1.02) : 1.0)
        .animation(
            isActive
                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                : .spring(response: 0.3, dampingFraction: 0.65),
            value: breathe
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isActive)
        .onChange(of: isActive) { _, active in
            if active { breathe = true } else { breathe = false }
        }
        .onAppear { if isActive { breathe = true } }
    }

    // MARK: - Background

    @ViewBuilder
    private var cellBackground: some View {
        switch cell.state {
        case .pending:
            if isActive {
                GameColors.activeGradient
            } else {
                Color.white.opacity(0.07)
            }
        case .active:
            GameColors.activeGradient
        case .correct:
            GameColors.correctGradient
        case .missed:
            GameColors.missedGradient
        }
    }

    // MARK: - Revealed Content

    @ViewBuilder
    private var revealedContent: some View {
        let hasUserAnswer = cell.userTranscript != nil && !cell.userTranscript!.isEmpty
        let isCorrect = cell.state == .correct

        if hasUserAnswer && !isCorrect {
            VStack(spacing: 2) {
                Text(cell.userTranscript!)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(GameColors.rojo.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .strikethrough(true, color: GameColors.rojo.opacity(0.5))
                    .padding(.horizontal, 4)

                Text(cell.expectedConjugation)
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(GameColors.rojo)
                    .shadow(color: GameColors.rojo.opacity(0.6), radius: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 2)
        } else {
            VStack(spacing: 3) {
                Image(systemName: isCorrect ? "checkmark" : "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(isCorrect ? GameColors.verde : GameColors.rojo)

                Text(cell.expectedConjugation)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(isCorrect ? GameColors.verde : GameColors.rojo)
                    .shadow(color: (isCorrect ? GameColors.verde : GameColors.rojo).opacity(0.55), radius: 4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Border

    private var borderColor: Color {
        switch cell.state {
        case .pending:  return isActive ? GameColors.gold : GameColors.cellBorder
        case .active:   return GameColors.gold
        case .correct:  return GameColors.verde.opacity(0.6)
        case .missed:   return GameColors.rojo.opacity(0.6)
        }
    }
}
