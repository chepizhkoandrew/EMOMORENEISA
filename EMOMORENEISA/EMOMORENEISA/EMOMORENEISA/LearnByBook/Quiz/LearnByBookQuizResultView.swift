import SwiftUI

/// The post-quiz screen: score + the same "Next steps" dock pattern Say It
/// Better uses for its own post-practice checkpoint (`NextStepsDockView`,
/// confirmed fully generic — no reuse changes needed).
struct LearnByBookQuizResultView: View {
    let result: LearnByBookQuizResult
    /// Whether a next topic exists in curriculum order — flips the
    /// secondary button between "Next topic" and "Back to topics".
    let hasNextTopic: Bool
    let onRetakeQuiz: () -> Void
    let onReviewLesson: () -> Void
    let onSecondaryAction: () -> Void

    private var isPerfect: Bool { result.correctCount == result.total }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer()

                scoreBadge

                Text(isPerfect ? L("Perfect!") : L("Quiz complete!"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.top, 20)

                Text(L("%d of %d correct", result.correctCount, result.total))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.top, 6)

                Spacer()

                NextStepsDockView(
                    primaryLabel: L("Retake quiz"),
                    secondaryLabel: hasNextTopic ? L("Next topic") : L("Back to topics"),
                    onPrimary: onRetakeQuiz,
                    onSecondary: onSecondaryAction,
                    tertiaryLabel: L("Review lesson again"),
                    onTertiary: onReviewLesson
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    private var scoreBadge: some View {
        ZStack {
            Circle()
                .fill((isPerfect ? GameColors.verde : AppColors.accent).opacity(0.15))
                .frame(width: 120, height: 120)
            Circle()
                .stroke(isPerfect ? GameColors.verde : AppColors.accent, lineWidth: 4)
                .frame(width: 120, height: 120)
            Text("\(result.correctCount)/\(result.total)")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(AppColors.textPrimary)
        }
    }
}
