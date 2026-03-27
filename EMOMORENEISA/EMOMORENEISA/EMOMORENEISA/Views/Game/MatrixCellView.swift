import SwiftUI

struct MatrixCellView: View {
    let cell: GameCell
    let isActive: Bool
    let timerProgress: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: isActive ? 2 : 1)
                )

            if isActive {
                TimerArcView(progress: timerProgress)
                    .padding(4)
            }

            if isActive {
                Text(cell.expectedConjugation)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(4)
            } else if cell.revealed {
                revealedContent
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }

    @ViewBuilder
    private var revealedContent: some View {
        let hasUserAnswer = cell.userTranscript != nil && !cell.userTranscript!.isEmpty
        let isCorrect = cell.state == .correct

        if hasUserAnswer && !isCorrect {
            VStack(spacing: 0) {
                Text(cell.userTranscript!)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.red.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 3)

                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.horizontal, 6)

                Text(cell.expectedConjugation)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.5), radius: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 3)
            }
            .padding(.vertical, 2)
        } else {
            Text(cell.expectedConjugation)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(isCorrect ? .green : .red)
                .shadow(color: isCorrect ? .green.opacity(0.5) : .red.opacity(0.5), radius: 4)
                .multilineTextAlignment(.center)
                .padding(4)
        }
    }

    private var backgroundColor: Color {
        switch cell.state {
        case .pending:  return Color.white.opacity(isActive ? 0.15 : 0.06)
        case .active:   return Color.blue.opacity(0.2)
        case .correct:  return Color.green.opacity(0.25)
        case .missed:   return Color.red.opacity(0.25)
        }
    }

    private var borderColor: Color {
        switch cell.state {
        case .pending:  return isActive ? Color.yellow : Color.white.opacity(0.2)
        case .active:   return Color.yellow
        case .correct:  return Color.green
        case .missed:   return Color.red
        }
    }
}
