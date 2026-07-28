import Foundation
import SwiftData

struct ESPProfile: Codable, Identifiable {
    let id: UUID
    var displayName: String?
    var level: String
    var nativeLanguage: String
    var focusTopics: [String]
    var currentStudyTopic: String?
    var learningNotes: String
    var sessionCount: Int
    var messageCount: Int
    var createdAt: Date
    var updatedAt: Date

    // v2 analytics fields
    var wordBank: [WordEntry]
    var phraseBank: [PhraseEntry]
    var errorLog: [ErrorEntry]
    var weakAreas: [String]
    var masteredAreas: [String]
    var lifeNotes: String
    var hobbies: [String]
    var whyLearning: String?
    var practiceStyle: String?
    var targetLevel: String?
    var exerciseHistory: [String]

    // Onboarding v3: pronoun + persona payload from the voice quiz.
    // Optional to keep legacy profiles decoding fine.
    var userPronoun: String?              // "he" | "she" | "they"
    var onboardingProfile: OnboardingProfile?

    // Single source of truth for "has this user finished onboarding at all"
    // (feature-tour carousel + voice quiz together) — gates both, and is the
    // one field QA flips in Supabase directly to force a replay on relaunch.
    var hasCompletedOnboarding: Bool

    // nil until the user explicitly accepts the standalone in-app AI-data-
    // sharing disclosure (AIDisclosureView) — gates every signed-in user
    // (new and existing) per Apple 5.1.1(i)/5.1.2(i).
    var aiDisclosureAcceptedAt: Date?

    // Graduated level system: replaces `level`'s 3-way granularity for
    // deciding how much Spanish vs. native language the tutor uses. `level`
    // itself stays populated (see `learnerStageEnum`'s bridge) since it's
    // still read by a couple of legacy `levelEnum` call sites.
    var learnerStage: String
    var immersionMode: String
    var absoluteBeginnerOverride: Bool
    var showInlineTranslations: Bool
    var autoSuggestLevelUp: Bool
    var stageProgressCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case displayName        = "display_name"
        case level
        case nativeLanguage     = "native_language"
        case focusTopics        = "focus_topics"
        case currentStudyTopic  = "current_study_topic"
        case learningNotes      = "learning_notes"
        case sessionCount       = "session_count"
        case messageCount       = "message_count"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case wordBank           = "word_bank"
        case phraseBank         = "phrase_bank"
        case errorLog           = "error_log"
        case weakAreas          = "weak_areas"
        case masteredAreas      = "mastered_areas"
        case lifeNotes          = "life_notes"
        case hobbies
        case whyLearning        = "why_learning"
        case practiceStyle      = "practice_style"
        case targetLevel        = "target_level"
        case exerciseHistory    = "exercise_history"
        case userPronoun        = "user_pronoun"
        case onboardingProfile  = "onboarding_profile"
        case hasCompletedOnboarding = "has_completed_onboarding"
        case aiDisclosureAcceptedAt = "ai_disclosure_accepted_at"
        case learnerStage             = "learner_stage"
        case immersionMode            = "immersion_mode"
        case absoluteBeginnerOverride = "absolute_beginner_override"
        case showInlineTranslations   = "show_inline_translations"
        case autoSuggestLevelUp       = "auto_suggest_level_up"
        case stageProgressCount       = "stage_progress_count"
    }

    init(
        id: UUID,
        displayName: String? = nil,
        level: String = "beginner",
        nativeLanguage: String = "English",
        focusTopics: [String] = [],
        currentStudyTopic: String? = nil,
        learningNotes: String = "",
        sessionCount: Int = 0,
        messageCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        wordBank: [WordEntry] = [],
        phraseBank: [PhraseEntry] = [],
        errorLog: [ErrorEntry] = [],
        weakAreas: [String] = [],
        masteredAreas: [String] = [],
        lifeNotes: String = "",
        hobbies: [String] = [],
        whyLearning: String? = nil,
        practiceStyle: String? = nil,
        targetLevel: String? = nil,
        exerciseHistory: [String] = [],
        userPronoun: String? = nil,
        onboardingProfile: OnboardingProfile? = nil,
        hasCompletedOnboarding: Bool = false,
        aiDisclosureAcceptedAt: Date? = nil,
        learnerStage: String = "beginner",
        immersionMode: String = "guided",
        absoluteBeginnerOverride: Bool = false,
        showInlineTranslations: Bool = true,
        autoSuggestLevelUp: Bool = true,
        stageProgressCount: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.level = level
        self.nativeLanguage = nativeLanguage
        self.focusTopics = focusTopics
        self.currentStudyTopic = currentStudyTopic
        self.learningNotes = learningNotes
        self.sessionCount = sessionCount
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.wordBank = wordBank
        self.phraseBank = phraseBank
        self.errorLog = errorLog
        self.weakAreas = weakAreas
        self.masteredAreas = masteredAreas
        self.lifeNotes = lifeNotes
        self.hobbies = hobbies
        self.whyLearning = whyLearning
        self.practiceStyle = practiceStyle
        self.targetLevel = targetLevel
        self.exerciseHistory = exerciseHistory
        self.userPronoun = userPronoun
        self.onboardingProfile = onboardingProfile
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.aiDisclosureAcceptedAt = aiDisclosureAcceptedAt
        self.learnerStage = learnerStage
        self.immersionMode = immersionMode
        self.absoluteBeginnerOverride = absoluteBeginnerOverride
        self.showInlineTranslations = showInlineTranslations
        self.autoSuggestLevelUp = autoSuggestLevelUp
        self.stageProgressCount = stageProgressCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self, forKey: .id)
        displayName       = try c.decodeIfPresent(String.self, forKey: .displayName)
        level             = try c.decode(String.self, forKey: .level)
        nativeLanguage    = (try? c.decode(String.self, forKey: .nativeLanguage)) ?? "English"
        focusTopics       = (try? c.decode([String].self, forKey: .focusTopics)) ?? []
        currentStudyTopic = try? c.decodeIfPresent(String.self, forKey: .currentStudyTopic)
        learningNotes     = (try? c.decode(String.self, forKey: .learningNotes)) ?? ""
        sessionCount      = (try? c.decode(Int.self, forKey: .sessionCount)) ?? 0
        messageCount      = (try? c.decode(Int.self, forKey: .messageCount)) ?? 0
        createdAt         = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt         = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        wordBank          = (try? c.decode([WordEntry].self, forKey: .wordBank)) ?? []
        phraseBank        = (try? c.decode([PhraseEntry].self, forKey: .phraseBank)) ?? []
        errorLog          = (try? c.decode([ErrorEntry].self, forKey: .errorLog)) ?? []
        weakAreas         = (try? c.decode([String].self, forKey: .weakAreas)) ?? []
        masteredAreas     = (try? c.decode([String].self, forKey: .masteredAreas)) ?? []
        lifeNotes         = (try? c.decode(String.self, forKey: .lifeNotes)) ?? ""
        hobbies           = (try? c.decode([String].self, forKey: .hobbies)) ?? []
        whyLearning       = try? c.decodeIfPresent(String.self, forKey: .whyLearning)
        practiceStyle     = try? c.decodeIfPresent(String.self, forKey: .practiceStyle)
        targetLevel       = try? c.decodeIfPresent(String.self, forKey: .targetLevel)
        exerciseHistory   = (try? c.decode([String].self, forKey: .exerciseHistory)) ?? []
        userPronoun       = try? c.decodeIfPresent(String.self, forKey: .userPronoun)
        onboardingProfile = try? c.decodeIfPresent(OnboardingProfile.self, forKey: .onboardingProfile)
        hasCompletedOnboarding = (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
        aiDisclosureAcceptedAt = try? c.decodeIfPresent(Date.self, forKey: .aiDisclosureAcceptedAt)

        // Backfill for rows that predate the `learner_stage` column: derive
        // from the legacy 3-way `level`, NOT `.absoluteBeginner` — existing
        // users must not regress to a zero-Spanish start just because this
        // column is new to them. Only genuinely new signups get
        // absoluteBeginner, via the DB column's own DEFAULT.
        learnerStage = (try? c.decodeIfPresent(String.self, forKey: .learnerStage))
            ?? LearnerStage.migrating(fromLegacy: level).rawValue
        immersionMode = (try? c.decode(String.self, forKey: .immersionMode)) ?? "guided"
        absoluteBeginnerOverride = (try? c.decode(Bool.self, forKey: .absoluteBeginnerOverride)) ?? false
        showInlineTranslations = (try? c.decode(Bool.self, forKey: .showInlineTranslations)) ?? true
        autoSuggestLevelUp = (try? c.decode(Bool.self, forKey: .autoSuggestLevelUp)) ?? true
        stageProgressCount = (try? c.decode(Int.self, forKey: .stageProgressCount)) ?? 0
    }

    var levelEnum: StudentLevel {
        get { StudentLevel(rawValue: level) ?? .beginner }
        set { level = newValue.rawValue }
    }

    var learnerStageEnum: LearnerStage {
        get { LearnerStage(rawValue: learnerStage) ?? .beginner }
        set { learnerStage = newValue.rawValue }
    }

    var immersionModeEnum: ImmersionMode {
        get { ImmersionMode(rawValue: immersionMode) ?? .guided }
        set { immersionMode = newValue.rawValue }
    }

    /// The stage that should actually govern tutoring behavior right now.
    /// `absoluteBeginnerOverride` is a manual escape hatch that masks
    /// `learnerStage` without overwriting it — turning it off returns the
    /// user to wherever their real stage was.
    var effectiveStage: LearnerStage {
        absoluteBeginnerOverride ? .absoluteBeginner : learnerStageEnum
    }

    /// Advances to the next stage (or just clears the override, if one was
    /// masking a more advanced stored stage) and resets progress tracking.
    /// Shared by the level-up banner's accept action and any other
    /// stage-advancing call site so the reset logic lives in one place.
    mutating func advanceStage() {
        if absoluteBeginnerOverride {
            absoluteBeginnerOverride = false
        } else if let next = learnerStageEnum.next {
            learnerStageEnum = next
        }
        stageProgressCount = 0
        level = learnerStageEnum.bridgedLegacyLevel
    }

    var wordsDueToday: [WordEntry] { wordBank.filter { $0.isDueToday } }
    var phrasesDueToday: [PhraseEntry] { phraseBank.filter { $0.isDueToday } }

    var profileDigest: String {
        var parts: [String] = []
        let due = wordsDueToday.prefix(5).map { $0.word }.joined(separator: ", ")
        if !due.isEmpty { parts.append("Palabras para repasar hoy: \(due)") }
        if !weakAreas.isEmpty { parts.append("Áreas débiles: \(weakAreas.prefix(3).joined(separator: ", "))") }
        if let why = whyLearning, !why.isEmpty { parts.append("Meta: \(why)") }
        if let style = practiceStyle, !style.isEmpty { parts.append("Estilo: \(style)") }
        if !lifeNotes.isEmpty { parts.append("Contexto personal: \(lifeNotes.prefix(120))") }
        if !exerciseHistory.isEmpty {
            parts.append("Últimos ejercicios: \(exerciseHistory.suffix(4).joined(separator: ", "))")
        }
        if let p = userPronoun, !p.isEmpty {
            parts.append("User pronoun: \(p). Address the user with the matching Ukrainian/Spanish endings; never mix genders mid-message.")
        }
        if let ob = onboardingProfile {
            if !ob.tutorCheatSheet.isEmpty {
                parts.append("=== Ficha del alumno (usa estos datos con naturalidad) ===\n\(ob.tutorCheatSheet)")
            }
            if !ob.cityFlavor.isEmpty {
                parts.append("City flavor: \(ob.cityFlavor)")
            }
            let narrative = ob.narrativeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !narrative.isEmpty {
                let short = narrative.split(separator: "\n").prefix(2).joined(separator: " ")
                parts.append("Sobre \(displayName ?? "el alumno"): \(short)")
            }
            if let lb = ob.levelBreakdown {
                var lines: [String] = ["=== Nivel del alumno (multi-eje, observado) ==="]
                if !lb.currentState.isEmpty { lines.append("Current: \(lb.currentState)") }
                lines.append("Overall: \(lb.overallBand) | Listening: \(lb.listening.band) | Speaking: \(lb.speaking.band) | Grammar: \(lb.grammar.band)")
                if !lb.listening.note.isEmpty { lines.append("Listening note: \(lb.listening.note)") }
                if !lb.speaking.note.isEmpty  { lines.append("Speaking note: \(lb.speaking.note)") }
                if !lb.grammar.note.isEmpty   { lines.append("Grammar note: \(lb.grammar.note)") }
                if !lb.goals.isEmpty {
                    lines.append("Goals:")
                    lines.append(contentsOf: lb.goals.prefix(5))
                }
                parts.append(lines.joined(separator: "\n"))
            }
        }
        return parts.joined(separator: "\n")
    }
}

enum StudentLevel: String, CaseIterable, Identifiable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        }
    }
    var maxTokens: Int {
        switch self {
        case .beginner:     return 300
        case .intermediate: return 512
        case .advanced:     return 650
        }
    }
}

/// Finer-grained level ladder that governs how much Spanish vs. native
/// language the tutor uses (see `PromptBuilder.languageGuidance`), replacing
/// `StudentLevel`'s 3-way granularity for that purpose. `StudentLevel`/
/// `ESPProfile.level` stay in the model as a read-only compatibility bridge
/// (`bridgedLegacyLevel`) for the couple of call sites still reading it.
enum LearnerStage: String, CaseIterable, Identifiable, Comparable {
    case absoluteBeginner  = "absolute_beginner"
    case beginner          = "beginner"
    case elementary        = "elementary"
    case intermediate      = "intermediate"
    case upperIntermediate = "upper_intermediate"
    case advanced          = "advanced"

    var id: String { rawValue }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: LearnerStage, rhs: LearnerStage) -> Bool { lhs.order < rhs.order }

    var displayLabel: String {
        switch self {
        case .absoluteBeginner:  return "Absolute Beginner"
        case .beginner:          return "Beginner"
        case .elementary:        return "Elementary"
        case .intermediate:      return "Intermediate"
        case .upperIntermediate: return "Upper Intermediate"
        case .advanced:          return "Advanced"
        }
    }

    /// Plain-language reminder of what this stage means for tutoring —
    /// shown under the progress bar in Level Settings.
    var tutoringDescription: String {
        switch self {
        case .absoluteBeginner:
            return "Your tutor speaks almost entirely in your native language, introducing a few simple Spanish words at a time."
        case .beginner:
            return "Your tutor mixes short, simple Spanish sentences with plenty of native-language support."
        case .elementary:
            return "Your tutor leans more into Spanish, still explaining new grammar in your native language."
        case .intermediate:
            return "Your tutor speaks mostly in Spanish, switching to your native language mainly for grammar notes."
        case .upperIntermediate:
            return "Your tutor speaks almost entirely in Spanish, with rare native-language asides."
        case .advanced:
            return "Your tutor speaks like a native speaker — full Spanish, no simplification."
        }
    }

    var maxTokens: Int {
        switch self {
        case .absoluteBeginner:  return 220
        case .beginner:          return 300
        case .elementary:        return 380
        case .intermediate:      return 512
        case .upperIntermediate: return 580
        case .advanced:          return 650
        }
    }

    var next: LearnerStage? {
        let cases = Self.allCases
        let nextOrder = order + 1
        return nextOrder < cases.count ? cases[nextOrder] : nil
    }

    /// Exchanges-at-or-above-this-stage required before the level-up banner
    /// suggests moving on (see `ProfileAnalystService`). Lower early on for a
    /// quick first nudge; nil at the top of the ladder (nothing to suggest).
    var levelUpThreshold: Int? {
        switch self {
        case .absoluteBeginner:  return 6
        case .beginner:          return 10
        case .elementary:        return 14
        case .intermediate:      return 18
        case .upperIntermediate: return 24
        case .advanced:          return nil
        }
    }

    /// Best-effort mapping back onto the legacy 3-way `StudentLevel` so any
    /// remaining `levelEnum` reader keeps getting something sane.
    var bridgedLegacyLevel: String {
        switch self {
        case .absoluteBeginner, .beginner, .elementary: return "beginner"
        case .intermediate:                             return "intermediate"
        case .upperIntermediate, .advanced:             return "advanced"
        }
    }

    /// Migration path from the legacy `level` field for profiles that
    /// predate `learner_stage` — deliberately never returns `.absoluteBeginner`
    /// here, since that would regress existing users to a zero-Spanish start.
    static func migrating(fromLegacy level: String) -> LearnerStage {
        switch level {
        case "intermediate": return .intermediate
        case "advanced":      return .advanced
        default:              return .beginner
        }
    }
}

/// Nudges the Spanish-vs-native ratio up or down from a user's measured
/// `LearnerStage` without changing the stage itself (see
/// `PromptBuilder.languageGuidance`).
enum ImmersionMode: String, CaseIterable, Identifiable {
    case gentle, guided, immersive

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .gentle:    return "Gentle"
        case .guided:    return "Guided"
        case .immersive: return "Immersive"
        }
    }

    var description: String {
        switch self {
        case .gentle:    return "More native language, ease in slowly"
        case .guided:    return "Balanced for your level"
        case .immersive: return "Push toward more Spanish"
        }
    }

    /// Shift applied to a `LearnerStage.order` lookup before resolving
    /// language-ratio guidance — clamped at the ladder's ends.
    var stageOrderShift: Int {
        switch self {
        case .gentle:    return -1
        case .guided:    return 0
        case .immersive: return 1
        }
    }
}

@Model
final class LocalStudentProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String?
    var level: String
    var nativeLanguage: String
    var focusTopics: [String]
    var currentStudyTopic: String?
    var learningNotes: String
    var sessionCount: Int
    var messageCount: Int
    var updatedAt: Date

    // v2 stored as encoded JSON strings (SwiftData cannot store [Codable] arrays directly)
    var wordBankJSON: Data
    var phraseBankJSON: Data
    var errorLogJSON: Data
    var weakAreas: [String]
    var masteredAreas: [String]
    var lifeNotes: String
    var hobbies: [String]
    var whyLearning: String?
    var practiceStyle: String?
    var targetLevel: String?
    var exerciseHistory: [String]
    var userPronoun: String? = nil
    var onboardingProfileJSON: Data = Data()
    var hasCompletedOnboarding: Bool = false
    var learnerStage: String = "beginner"
    var immersionMode: String = "guided"
    var absoluteBeginnerOverride: Bool = false
    var showInlineTranslations: Bool = true
    var autoSuggestLevelUp: Bool = true
    var stageProgressCount: Int = 0

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(from remote: ESPProfile) {
        self.id = remote.id
        self.displayName = remote.displayName
        self.level = remote.level
        self.nativeLanguage = remote.nativeLanguage
        self.focusTopics = remote.focusTopics
        self.currentStudyTopic = remote.currentStudyTopic
        self.learningNotes = remote.learningNotes
        self.sessionCount = remote.sessionCount
        self.messageCount = remote.messageCount
        self.updatedAt = remote.updatedAt
        self.wordBankJSON = (try? Self.encoder.encode(remote.wordBank)) ?? Data()
        self.phraseBankJSON = (try? Self.encoder.encode(remote.phraseBank)) ?? Data()
        self.errorLogJSON = (try? Self.encoder.encode(remote.errorLog)) ?? Data()
        self.weakAreas = remote.weakAreas
        self.masteredAreas = remote.masteredAreas
        self.lifeNotes = remote.lifeNotes
        self.hobbies = remote.hobbies
        self.whyLearning = remote.whyLearning
        self.practiceStyle = remote.practiceStyle
        self.targetLevel = remote.targetLevel
        self.exerciseHistory = remote.exerciseHistory
        self.userPronoun = remote.userPronoun
        self.onboardingProfileJSON = (try? Self.encoder.encode(remote.onboardingProfile)) ?? Data()
        self.hasCompletedOnboarding = remote.hasCompletedOnboarding
        self.learnerStage = remote.learnerStage
        self.immersionMode = remote.immersionMode
        self.absoluteBeginnerOverride = remote.absoluteBeginnerOverride
        self.showInlineTranslations = remote.showInlineTranslations
        self.autoSuggestLevelUp = remote.autoSuggestLevelUp
        self.stageProgressCount = remote.stageProgressCount
    }

    func update(from remote: ESPProfile) {
        displayName = remote.displayName
        level = remote.level
        nativeLanguage = remote.nativeLanguage
        focusTopics = remote.focusTopics
        currentStudyTopic = remote.currentStudyTopic
        learningNotes = remote.learningNotes
        sessionCount = remote.sessionCount
        messageCount = remote.messageCount
        updatedAt = remote.updatedAt
        wordBankJSON = (try? Self.encoder.encode(remote.wordBank)) ?? Data()
        phraseBankJSON = (try? Self.encoder.encode(remote.phraseBank)) ?? Data()
        errorLogJSON = (try? Self.encoder.encode(remote.errorLog)) ?? Data()
        weakAreas = remote.weakAreas
        masteredAreas = remote.masteredAreas
        lifeNotes = remote.lifeNotes
        hobbies = remote.hobbies
        whyLearning = remote.whyLearning
        practiceStyle = remote.practiceStyle
        targetLevel = remote.targetLevel
        exerciseHistory = remote.exerciseHistory
        userPronoun = remote.userPronoun
        onboardingProfileJSON = (try? Self.encoder.encode(remote.onboardingProfile)) ?? Data()
        hasCompletedOnboarding = remote.hasCompletedOnboarding
        learnerStage = remote.learnerStage
        immersionMode = remote.immersionMode
        absoluteBeginnerOverride = remote.absoluteBeginnerOverride
        showInlineTranslations = remote.showInlineTranslations
        autoSuggestLevelUp = remote.autoSuggestLevelUp
        stageProgressCount = remote.stageProgressCount
    }

    var wordBank: [WordEntry] {
        get { (try? Self.decoder.decode([WordEntry].self, from: wordBankJSON)) ?? [] }
        set { wordBankJSON = (try? Self.encoder.encode(newValue)) ?? Data() }
    }
    var phraseBank: [PhraseEntry] {
        get { (try? Self.decoder.decode([PhraseEntry].self, from: phraseBankJSON)) ?? [] }
        set { phraseBankJSON = (try? Self.encoder.encode(newValue)) ?? Data() }
    }
    var errorLog: [ErrorEntry] {
        get { (try? Self.decoder.decode([ErrorEntry].self, from: errorLogJSON)) ?? [] }
        set { errorLogJSON = (try? Self.encoder.encode(newValue)) ?? Data() }
    }
}
