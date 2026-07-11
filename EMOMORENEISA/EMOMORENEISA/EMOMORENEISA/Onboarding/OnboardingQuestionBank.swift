import Foundation

// Onboarding question bank — v1.3. MUST stay 1:1 with
// server/scripts/render-onboarding-assets.js. The client relies on the
// pre-rendered `.aac` assets shipped in the app bundle, keyed by
// (language, gender, slot). Any wording change here also requires re-rendering
// the assets and bumping ONBOARDING_QUIZ_VERSION on the server.

enum OnboardingSlot: String, CaseIterable {
    // Standard block. Q5 was split in R14 into q5 (rate 3 skills) + q5b
    // (what to improve most), so the flow now has one extra step.
    case q1, q2, q3, q4, q5, q5b, q6, q7
    // Adaptive
    case q8, q9
    // Finale
    case q10, q11
    // Non-question slots
    case reprompt, fallback

    var isAdaptive: Bool { self == .q8 || self == .q9 }
    var isPreRecorded: Bool { !isAdaptive }
    // Q1 (name + country/city) was dropped from the runtime flow — the name is
    // already captured in the pre-form. The enum case is kept so bundled assets
    // and legacy stored answers still resolve, but it is not part of the
    // visible progress track anymore.
    var indexForProgress: Int? {
        switch self {
        case .q2: return 0; case .q3: return 1; case .q4: return 2
        case .q5: return 3; case .q5b: return 4; case .q6: return 5
        case .q7: return 6
        case .q8: return 7; case .q9: return 8
        case .q10: return 9; case .q11: return 10
        default: return nil
        }
    }
}

enum OnboardingQuestionBank {
    static let progressCount = 11

    /// Displayable question text (used for the subtitle strip). Adaptive
    /// slots return "" — their text is filled in by the analyst at runtime.
    static func text(for slot: OnboardingSlot,
                     language: OnboardingQuizLanguage,
                     pronoun: UserPronoun) -> String {
        switch language {
        case .en: return enBank[slot] ?? ""
        case .uk:
            switch pronoun {
            case .he:   return ukHe[slot] ?? ""
            case .she:  return ukShe[slot] ?? ""
            case .they: return ukThey[slot] ?? ""
            }
        }
    }

    /// Path to the pre-rendered `.aac` in the app bundle for a pre-recorded
    /// slot. Adaptive slots have no bundle asset and return nil.
    static func bundleAudioURL(for slot: OnboardingSlot,
                               language: OnboardingQuizLanguage,
                               pronoun: UserPronoun) -> URL? {
        guard slot.isPreRecorded else { return nil }
        let langFolder = language.rawValue
        let genderFolder: String
        switch language {
        case .en: genderFolder = "neutral"
        case .uk:
            switch pronoun {
            case .he: genderFolder = "he"
            case .she: genderFolder = "she"
            case .they: genderFolder = "they"
            }
        }
        // Flat, uniquely-named resource — Xcode's synchronized group copies
        // this folder's resources into the bundle root without preserving
        // subdirectory structure, so e.g. "q6.aac" from en/neutral and
        // uk/he would otherwise collide ("Multiple commands produce...").
        // The lang/gender folders on disk are just for human organization.
        let flatName = "\(slot.rawValue)_\(langFolder)_\(genderFolder)"
        return Bundle.main.url(forResource: flatName, withExtension: "aac")
    }

    /// Language hint passed to the STT service for user answers.
    static func sttLanguageHint(for pronoun: UserPronoun, quizLanguage: OnboardingQuizLanguage) -> String? {
        // We do NOT constrain STT to the quiz language — users can answer in
        // any native language. Returning nil lets Whisper auto-detect.
        return nil
    }

    // MARK: - Bank (kept in sync with render-onboarding-assets.js)

    private static let enBank: [OnboardingSlot: String] = [
        .q1:  "So — what should I call you, and what country and city are you in these days?",
        .q2:  "What do you do in life — working, studying, raising kids?",
        .q3:  "Why do you want to learn Spanish? For work? To connect with people — with anyone in particular? Or just for fun, or for school?",
        .q4:  "How long have you been learning Spanish? Do you go to a school, use other apps, or are you just starting out and not sure where to begin?",
        .q5:  "How would you rate your Spanish right now — your understanding, your grammar, and your speaking, each on its own?",
        .q5b: "And what would you like to improve most — learning new words and grammar, or speaking without fear?",
        .q6:  "Quick thing — try answering this one in Spanish, as best as you can, nice and slow. Tell me one sentence about your daily routine: what you do in the morning, if you live alone or with someone, where you work, and what you like doing in your free time.",
        .q7:  "Tell me one small, totally random thing about yourself — a pet, a weird hobby, your best friend's name — whatever pops into your head first.",
        .q10: "Imagine you already speak Spanish fluently — what changes in your life?",
        .q11: "And the last one — the hardest. Listen carefully and don't take it the wrong way… who do you like more, dogs or cats? Dogs, right? Tell me you like dogs more.",
        .reprompt: "One more time? I didn't quite catch that.",
        .fallback: "Tell me about a place you've been to that surprised you — or one you'd love to visit someday and why."
    ]

    private static let ukHe: [OnboardingSlot: String] = [
        .q1:  "То як тебе звати, і в якій країні та місті ти зараз живеш?",
        .q2:  "Чим ти займаєшся в житті — працюєш, вчишся, ростиш дітей?",
        .q3:  "Чому ти хочеш вивчити іспанську? Для роботи? Щоб спілкуватися з людьми — з кимось конкретно? Чи просто для задоволення, чи для навчання?",
        .q4:  "Як довго ти вчиш іспанську? Ходиш до школи, користуєшся іншими додатками, чи це самий початок і ти ще не знаєш, з чого стартувати?",
        .q5:  "Як ти оцінюєш свою іспанську зараз? Окремо - розуміння, граматику, та спілкування.",
        .q5b: "А що ти хотів би покращити найбільше — вивчити нові слова й граматику, чи почати говорити без страху?",
        .q6:  "Швидке прохання — спробуй відповісти на це іспанською, наскільки зможеш, повільно і спокійно. Розкажи одним реченням про свій звичайний день: що робиш зранку, живеш сам чи з кимось, де працюєш і чим любиш займатися у вільний час.",
        .q7:  "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращого друга — що першим спаде на думку.",
        .q10: "Уяви, що ти вже вільно говориш іспанською — що зміниться у твоєму житті?",
        .q11: "І останнє — найскладніше. Слухай уважно і не зрозумій мене неправильно… кого ти любиш більше, собак чи котів? Собак, правда ж? Скажи, що любиш собак більше.",
        .reprompt: "Ще раз? Я не зовсім розчув.",
        .fallback: "Розкажи про місце, яке тебе здивувало — або про місце, яке ти хотів би відвідати й чому."
    ]

    private static let ukShe: [OnboardingSlot: String] = [
        .q1:  "То як тебе звати, і в якій країні та місті ти зараз живеш?",
        .q2:  "Чим ти займаєшся в житті — працюєш, вчишся, ростиш дітей?",
        .q3:  "Чому ти хочеш вивчити іспанську? Для роботи? Щоб спілкуватися з людьми — з кимось конкретно? Чи просто для задоволення, чи для навчання?",
        .q4:  "Як довго ти вчиш іспанську? Ходиш до школи, користуєшся іншими додатками, чи це самий початок і ти ще не знаєш, з чого стартувати?",
        .q5:  "Як ти оцінюєш свою іспанську зараз? Окремо - розуміння, граматику, та спілкування.",
        .q5b: "А що ти хотіла б покращити найбільше — вивчити нові слова й граматику, чи почати говорити без страху?",
        .q6:  "Швидке прохання — спробуй відповісти на це іспанською, наскільки зможеш, повільно і спокійно. Розкажи одним реченням про свій звичайний день: що робиш зранку, живеш сама чи з кимось, де працюєш і чим любиш займатися у вільний час.",
        .q7:  "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращої подруги — що першим спаде на думку.",
        .q10: "Уяви, що ти вже вільно говориш іспанською — що зміниться у твоєму житті?",
        .q11: "І останнє — найскладніше. Слухай уважно і не зрозумій мене неправильно… кого ти любиш більше, собак чи котів? Собак, правда ж? Скажи, що любиш собак більше.",
        .reprompt: "Ще раз? Я не зовсім розчула.",
        .fallback: "Розкажи про місце, яке тебе здивувало — або про місце, яке ти хотіла б відвідати й чому."
    ]

    private static let ukThey: [OnboardingSlot: String] = [
        .q1:  "То як тебе звати, і в якій країні та місті ти зараз живеш?",
        .q2:  "Чим ти займаєшся в житті — працюєш, вчишся, ростиш дітей?",
        .q3:  "Чому ти хочеш вивчити іспанську? Для роботи? Щоб спілкуватися з людьми — з кимось конкретно? Чи просто для задоволення, чи для навчання?",
        .q4:  "Як довго ти вчиш іспанську? Ходиш до школи, користуєшся іншими додатками, чи це самий початок і ти ще не знаєш, з чого стартувати?",
        .q5:  "Як ти оцінюєш свою іспанську зараз? Окремо - розуміння, граматику, та спілкування.",
        .q5b: "А що хочеться покращити найбільше — вивчити нові слова й граматику, чи почати говорити без страху?",
        .q6:  "Швидке прохання — спробуй відповісти на це іспанською, наскільки зможеш, повільно і спокійно. Розкажи одним реченням про свій звичайний день: що робиш зранку, живеш одне чи з кимось, де працюєш і чим любиш займатися у вільний час.",
        .q7:  "Розкажи щось маленьке й геть випадкове про себе — про домашнього улюбленця, дивне хобі, ім'я найкращого друга — що першим спаде на думку.",
        .q10: "Уяви, що ти вже вільно говориш іспанською — що зміниться у твоєму житті?",
        .q11: "І останнє — найскладніше. Слухай уважно і не зрозумій мене неправильно… кого ти любиш більше, собак чи котів? Собак, правда ж? Скажи, що любиш собак більше.",
        .reprompt: "Ще раз? Я не зовсім розчув тебе.",
        .fallback: "Розкажи про місце, яке тебе здивувало — або про місце, яке ти хотів би відвідати й чому."
    ]
}
