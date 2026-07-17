import SwiftUI

// Phase A of the onboarding quiz — a silent form (no audio) that collects
// the inputs the voice quiz needs before it can start: quiz language, name,
// and pronoun. The name step is skipped when Sign in with Apple already
// supplied one (see `stepSequence`) — Apple's Sign in with Apple guidelines
// require reusing that value rather than asking again. Language comes first
// because the pronoun step's labels are bilingual once a Ukrainian quiz is
// chosen (see `pronounLabel`) — asking it last would render pronoun options
// in the wrong/default language for that entire step. Each field lives on
// its own dedicated screen so the flow reads calm and tidy. Continue on
// the final screen fires `onContinue`.

struct PreOnboardingFormView: View {
    @Bindable var store: OnboardingStore
    var onContinue: () -> Void

    @State private var step: Int = 0
    @FocusState private var nameFieldFocused: Bool

    private enum FormStep { case language, name, pronoun }

    // Sign in with Apple already supplies a name — Apple's Sign in with Apple
    // guidelines (and App Review) require reusing it instead of asking again,
    // so the name step is skipped entirely whenever one is already known.
    private var stepSequence: [FormStep] {
        store.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? [.language, .name, .pronoun]
            : [.language, .pronoun]
    }
    private var totalSteps: Int { stepSequence.count }
    private var currentFormStep: FormStep { stepSequence[min(step, stepSequence.count - 1)] }

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

                VStack(alignment: currentFormStep == .name ? .center : .leading, spacing: 24) {
                    stepHeader

                    Group {
                        switch currentFormStep {
                        case .language: languagePicker
                        case .name: nameField
                        case .pronoun: pronounPicker
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: currentFormStep == .name ? .center : .leading)

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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
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
        switch currentFormStep {
        case .language:
            // Language hasn't been picked yet at this point, so this one
            // header still follows the app's global UI language.
            headerBlock(title: L("Your language"), subtitle: nil)
        case .name:
            headerBlock(title: "¡Hola!",
                        subtitle: quizText(en: "First — what should I call you?",
                                            uk: "Перш за все — як тебе звати?"),
                        centered: true)
        case .pronoun:
            headerBlock(title: quizText(en: "Nice to meet you!", uk: "Приємно познайомитись!"),
                        subtitle: quizText(en: "How should I refer to you?",
                                           uk: "Як мені до тебе звертатися?"))
        }
    }

    private func headerBlock(title: String, subtitle: String?, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(centered ? .center : .leading)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Step 2: name

    private var nameField: some View {
        TextField("", text: $store.name, prompt: Text(quizText(en: "First name", uk: "Ім'я")).foregroundColor(AppColors.textTertiary))
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

    // MARK: - Step 3: pronoun

    private var pronounPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(quizText(en: "Your pronoun", uk: "Твій займенник"))
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
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
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

    // MARK: - Step 1: language

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                ForEach(OnboardingQuizLanguage.allCases) { lang in
                    Button {
                        store.quizLanguage = lang
                    } label: {
                        HStack(spacing: 12) {
                            Text(lang.flag)
                                .font(.system(size: 22, design: .rounded))
                            Text(lang.displayLabel)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(store.quizLanguage == lang ? .black : AppColors.textPrimary)
                            Spacer()
                            if store.quizLanguage == lang {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
        step == totalSteps - 1
            ? quizText(en: "Start the quiz", uk: "Почати квіз")
            : quizText(en: "Continue", uk: "Продовжити")
    }

    private var isCurrentStepValid: Bool {
        switch currentFormStep {
        case .language: return true
        case .name: return !store.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .pronoun: return store.pronoun != nil
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

    /// Text keyed to the quiz language the user just picked in step 0 — NOT
    /// `L()`'s global app-UI language, which may still be English even when
    /// Ukrainian was chosen for this quiz. Only `pronounLabel` had this right
    /// before; the name/pronoun step headers were still using `L()` and so
    /// silently stayed in English/Spanish regardless of the quiz-language
    /// choice.
    private func quizText(en: String, uk: String) -> String {
        store.quizLanguage == .uk ? uk : en
    }
}
