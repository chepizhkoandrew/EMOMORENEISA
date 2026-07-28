import SwiftUI

/// One page of Learn by the Book's voice quiz — always answered by SPEAKING,
/// never by tapping or typing (see `LearnByBookQuizQuestion`'s doc comment
/// for why that's the whole point of this mode). Mirrors `QuizQuestionView`'s
/// prompt/CTA visual language, but the "tap an option" step is replaced by a
/// record → transcribe → judge loop modeled on `GameEngine`'s verb-game
/// mechanic (`SpokenAnswerJudge` + `ProxyClient.phraseCheck`).
struct LearnByBookVoiceAnswerQuestionView: View {
    let question: LearnByBookQuizQuestion
    let questionNumber: Int
    let totalQuestions: Int
    let onNext: (Bool) -> Void

    private enum AnswerState: Equatable {
        case idle
        case recording
        case transcribing
        case judging
        case revealed(correct: Bool, transcript: String)
    }

    @State private var state: AnswerState = .idle
    @State private var recorder = AudioRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer().frame(height: 8)

            Text(question.prompt(for: LocalizationManager.shared.language))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 16) {
                micButton
                statusLabel
            }
            .frame(maxWidth: .infinity)

            if case .revealed(let correct, let transcript) = state {
                feedbackCard(correct: correct, transcript: transcript)
            }

            Spacer()

            footerButtons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .onChange(of: question.id) { _, _ in
            recorder.cancel()
            state = .idle
        }
    }

    // MARK: - Mic button

    private var micButton: some View {
        Button {
            handleTap()
        } label: {
            ZStack {
                Circle()
                    .fill(micFillColor)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(micStrokeColor, lineWidth: 2))

                switch state {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.black)
                case .recording:
                    VoiceWaveformView(
                        audioLevel: recorder.audioLevel,
                        color: .white,
                        barCount: 5,
                        maxHeight: 32,
                        barWidth: 4,
                        spacing: 4
                    )
                case .transcribing, .judging:
                    ProgressView().tint(.white).scaleEffect(1.1)
                case .revealed(let correct, _):
                    Image(systemName: correct ? "checkmark" : "xmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isMicDisabled)
    }

    private var isMicDisabled: Bool {
        switch state {
        case .transcribing, .judging, .revealed: return true
        case .idle, .recording: return false
        }
    }

    private var micFillColor: Color {
        switch state {
        case .idle: return AppColors.accent
        case .recording: return .red
        case .transcribing, .judging: return AppColors.inputBackground
        case .revealed(let correct, _): return correct ? GameColors.verde : GameColors.rojo
        }
    }

    private var micStrokeColor: Color {
        switch state {
        case .recording: return Color.red.opacity(0.4)
        default: return AppColors.cardBorder
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch state {
        case .idle:
            Text(L("Tap to answer"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        case .recording:
            Text(L("Listening… tap to stop"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.red.opacity(0.85))
        case .transcribing:
            Text(L("Transcribing…"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        case .judging:
            Text(L("Checking…"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(AppColors.textTertiary)
        case .revealed:
            EmptyView()
        }
    }

    // MARK: - Feedback

    private func feedbackCard(correct: Bool, transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(correct ? L("Correct!") : L("Not quite — \"%@\" is what we were going for.", question.targetSpanish))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(correct ? GameColors.verde : GameColors.rojo)
            if !transcript.isEmpty {
                Text(L("You said: \"%@\"", transcript))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background((correct ? GameColors.verde : GameColors.rojo).opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke((correct ? GameColors.verde : GameColors.rojo).opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerButtons: some View {
        if case .revealed(let correct, _) = state {
            VStack(spacing: 12) {
                if !correct {
                    Button {
                        state = .idle
                    } label: {
                        Text(L("Try again"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    onNext(correct)
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
    }

    // MARK: - Recording flow

    private func handleTap() {
        switch state {
        case .idle:
            do {
                try recorder.start()
                state = .recording
            } catch {}
        case .recording:
            state = .transcribing
            Task {
                let transcript = await recorder.stopAndTranscribe()
                await MainActor.run { state = .judging }
                let correct = await SpokenAnswerJudge.judge(
                    transcribed: transcript,
                    expected: question.targetSpanish
                ) { normalizedTranscript in
                    try await ProxyClient.shared.phraseCheck(
                        transcript: normalizedTranscript,
                        expected: question.targetSpanish
                    )
                }
                await MainActor.run {
                    state = .revealed(correct: correct, transcript: transcript)
                }
            }
        case .transcribing, .judging, .revealed:
            break
        }
    }
}
