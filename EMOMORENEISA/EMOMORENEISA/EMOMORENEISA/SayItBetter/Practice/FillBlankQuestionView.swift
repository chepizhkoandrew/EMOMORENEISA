import SwiftUI

/// One fill-in-the-blank carousel page. Answer matching is case- and
/// accent-insensitive against the curated `acceptedAnswers` set — the same
/// content-authoring shape Word Swap will need later for its
/// context-dependent "which upgrade fits this sentence" prompts.
struct FillBlankQuestionView: View {
    let question: QuizQuestion
    let questionNumber: Int
    let totalQuestions: Int
    let onNext: (Bool) -> Void

    @State private var input: String = ""
    @State private var checked = false
    @FocusState private var focused: Bool

    private var template: String { question.sentenceTemplate ?? "" }
    private var accepted: [String] { question.acceptedAnswers ?? [] }
    private var isCorrect: Bool {
        accepted.contains { normalize($0) == normalize(input) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer().frame(height: 8)

            Text(question.prompt(for: LocalizationManager.shared.language))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textSecondary)

            sentenceView
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L("Type the missing word"), text: $input)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(checked ? feedbackBackground : AppColors.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(checked ? feedbackBorder : AppColors.inputBorder, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(checked)
                .focused($focused)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)

            if checked {
                Text(isCorrect ? L("Correct!") : L("Not quite — \"%@\" is what we were going for.", accepted.first ?? ""))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(isCorrect ? GameColors.verde : GameColors.rojo)
            }

            Spacer()

            Button {
                if checked {
                    onNext(isCorrect)
                } else {
                    focused = false
                    withAnimation(.easeOut(duration: 0.18)) { checked = true }
                }
            } label: {
                Text(buttonLabel)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!checked && input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private var buttonLabel: String {
        guard checked else { return L("Check") }
        return questionNumber == totalQuestions ? L("Finish") : L("Next")
    }

    private var feedbackBackground: Color { (isCorrect ? GameColors.verde : GameColors.rojo).opacity(0.16) }
    private var feedbackBorder: Color { (isCorrect ? GameColors.verde : GameColors.rojo).opacity(0.6) }

    /// Renders the template's "___" placeholder as a visually distinct blank
    /// rather than a literal string of underscores.
    private var sentenceView: Text {
        let parts = template.components(separatedBy: "___")
        guard parts.count == 2 else { return Text(template) }
        var blank = AttributedString(checked ? (accepted.first ?? "___") : "___")
        blank.foregroundColor = AppColors.accent
        return Text(parts[0]) + Text(blank) + Text(parts[1])
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}
