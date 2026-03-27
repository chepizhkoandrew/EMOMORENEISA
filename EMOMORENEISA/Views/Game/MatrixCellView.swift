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

            if cell.revealed || isActive {
                Text(cell.expectedConjugation)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .padding(4)
            } else {
                Image(systemName: stateIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
            }
        }
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
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

    private var textColor: Color {
        switch cell.state {
        case .pending:  return .white
        case .active:   return .white
        case .correct:  return .green
        case .missed:   return .red
        }
    }

    private var stateIcon: String {
        switch cell.state {
        case .pending:  return "questionmark"
        case .active:   return "mic.fill"
        case .correct:  return "checkmark"
        case .missed:   return "xmark"
        }
    }
}
