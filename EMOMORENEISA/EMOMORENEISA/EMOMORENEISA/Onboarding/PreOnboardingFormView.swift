import SwiftUI

// Phase A of the onboarding quiz — a silent 3-step form (no audio) that
// collects the three inputs the voice quiz needs before it can start:
// name, pronoun, and quiz language. Each field lives on its own dedicated
// screen so the flow reads calm and tidy. Continue on the final screen
// fires `onContinue`.

struct PreOnboardingFormView: View {
    @Bindable var store: OnboardingStore
    var onContinue: () -> Void

    // 0 = name, 1 = pronoun, 2 = language
    @State private var step: Int = 0
    private let totalSteps: Int = 3
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ZStack {
            ZStack {
                GameBackground()
                DreamParticlesView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            .contentShape(Rectangle())
            .onTapGesture { nameFieldFocused = false }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Spacer(minLength: 20)

                VStack(alignment: step == 0 ? .center : .leading, spacing: 24) {
                    stepHeader

                    Group {
                        switch step {
                        case 0: nameField
                        case 1: pronounPicker
                        default: languagePicker
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: step == 0 ? .center : .leading)

                Spacer(minLength: 20)

                continueButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
            }
        }
        .onAppear {
            // Belt-and-braces: silence any speech-bubble / intro-slide audio
            // that might still be alive when the pre-form materialises.
            OnboardAudioManager.shared.stop()
            BackgroundMusicPlayer.shared.fadeOut(duration: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                OnboardAudioManager.shared.stop()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardAudioManager.shared.stop()
            }
        }
    }

    // MARK: - Top bar (back + progress dots)

    private var topBar: some View {
        HStack(alignment: .center) {
            backArrow
            Spacer()
            progressDots
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var backArrow: some View {
        if step > 0 {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.yellow : Color.white.opacity(0.3))
                    .frame(width: i == step ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.35), value: step)
            }
        }
    }

    // MARK: - Step header

    @ViewBuilder
    private var stepHeader: some View {
        switch step {
        case 0:
            headerBlock(title: "¡Hola!",
                        subtitle: L("First — what should I call you?"),
                        centered: true)
        case 1:
            headerBlock(title: L("Nice to meet you!"),
                        subtitle: L("How should I refer to you?"))
        default:
            headerBlock(title: L("Your language"),
                        subtitle: L("Language choice"))
        }
    }

    private func headerBlock(title: String, subtitle: String, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
            Text(subtitle)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(centered ? .center : .leading)
        }
        .padding(.top, 4)
    }

    // MARK: - Step 1: name

    private var nameField: some View {
        TextField("", text: $store.name, prompt: Text(L("First name")).foregroundColor(AppColors.textTertiary))
            .focused($nameFieldFocused)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(true)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundColor(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(AppColors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.inputBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Step 2: pronoun

    private var pronounPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(L("Your pronoun"))
            VStack(spacing: 6) {
                ForEach(UserPronoun.allCases) { p in
                    Button {
                        store.pronoun = p
                    } label: {
                        HStack(spacing: 12) {
                            Text(pronounLabel(p))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(store.pronoun == p ? .black : AppColors.textPrimary)
                            Spacer()
                            if store.pronoun == p {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(store.pronoun == p ? Color.yellow : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(store.pronoun == p ? Color.clear : AppColors.cardBorder,
                                        lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Step 3: language

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                ForEach(OnboardingQuizLanguage.allCases) { lang in
                    Button {
                        store.quizLanguage = lang
                    } label: {
                        HStack(spacing: 12) {
                            Text(lang.flag)
                                .font(.system(size: 22))
                            Text(lang.displayLabel)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(store.quizLanguage == lang ? .black : AppColors.textPrimary)
                            Spacer()
                            if store.quizLanguage == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(store.quizLanguage == lang ? Color.yellow : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(store.quizLanguage == lang ? Color.clear : AppColors.cardBorder,
                                        lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button {
            handleContinue()
        } label: {
            Text(continueLabel)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isCurrentStepValid ? Color.yellow : Color.yellow.opacity(0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isCurrentStepValid)
    }

    private var continueLabel: String {
        step == totalSteps - 1 ? L("Start the quiz") : L("Continue")
    }

    private var isCurrentStepValid: Bool {
        switch step {
        case 0: return !store.name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return store.pronoun != nil
        default: return true
        }
    }

    private func handleContinue() {
        guard isCurrentStepValid else { return }
        if step < totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.22)) { step += 1 }
        } else if store.preFormValid {
            onContinue()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(AppColors.textTertiary)
            .textCase(.uppercase)
    }

    private func pronounLabel(_ p: UserPronoun) -> String {
        switch store.quizLanguage {
        case .en: return p.displayLabel
        case .uk: return "\(p.ukLabel) · \(p.displayLabel)"
        }
    }
}
