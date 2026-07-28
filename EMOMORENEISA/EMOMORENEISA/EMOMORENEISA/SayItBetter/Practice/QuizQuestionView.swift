import SwiftUI

/// One multiple-choice carousel page. Tapping an option reveals correct/
/// incorrect immediately (light, per-question feedback); the deeper
/// "here's the pattern in what you missed" synthesis happens once, after the
/// whole carousel, in Madrid's after-practice feedback message — not here.
struct QuizQuestionView: View {
    let question: QuizQuestion
    let questionNumber: Int
    let totalQuestions: Int
    let initialSelectedIndex: Int?
    let onNext: (Bool) -> Void

    @State private var selectedIndex: Int?

    private var options: [String] { question.options ?? [] }
    private var correctIndex: Int { question.correctOptionIndex ?? -1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer().frame(height: 8)

            Text(question.prompt(for: LocalizationManager.shared.language))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    optionRow(option, index: index)
                }
            }

            Spacer()

            if selectedIndex != nil {
                Button {
                    onNext(selectedIndex == correctIndex)
                } label: {
                    Text(questionNumber == totalQuestions ? L("Finish") : L("Next"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .onAppear { selectedIndex = initialSelectedIndex }
    }

    @ViewBuilder
    private func optionRow(_ option: String, index: Int) -> some View {
        Button {
            guard selectedIndex == nil else { return }
            withAnimation(.easeOut(duration: 0.18)) { selectedIndex = index }
        } label: {
            HStack {
                Text(option)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(rowTextColor(for: index))
                Spacer()
                if selectedIndex != nil, index == correctIndex {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(GameColors.verde)
                } else if selectedIndex == index {
                    Image(systemName: "xmark.circle.fill").foregroundColor(GameColors.rojo)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(rowBackground(for: index))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(rowBorder(for: index), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(selectedIndex != nil)
    }

    private func rowBackground(for index: Int) -> Color {
        guard let selectedIndex else { return AppColors.cardBackground }
        if index == correctIndex { return GameColors.verde.opacity(0.16) }
        if index == selectedIndex { return GameColors.rojo.opacity(0.16) }
        return AppColors.cardBackground
    }

    private func rowBorder(for index: Int) -> Color {
        guard let selectedIndex else { return AppColors.cardBorder }
        if index == correctIndex { return GameColors.verde.opacity(0.6) }
        if index == selectedIndex { return GameColors.rojo.opacity(0.6) }
        return AppColors.cardBorder
    }

    private func rowTextColor(for index: Int) -> Color {
        guard selectedIndex != nil else { return AppColors.textPrimary }
        return (index == correctIndex || index == selectedIndex) ? AppColors.textPrimary : AppColors.textSecondary
    }
}
