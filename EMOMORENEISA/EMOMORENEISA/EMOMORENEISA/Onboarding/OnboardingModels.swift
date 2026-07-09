import Foundation

// Voice-onboarding quiz — persistent data model.
// Kept in the Onboarding submodule so we do not touch the rest of the app.

enum UserPronoun: String, Codable, CaseIterable, Identifiable {
    case he, she, they
    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .he:   return "He / Him"
        case .she:  return "She / Her"
        case .they: return "They / Them"
        }
    }

    /// Ukrainian short label used in the pre-form segmented picker.
    var ukLabel: String {
        switch self {
        case .he:   return "Він"
        case .she:  return "Вона"
        case .they: return "Вони"
        }
    }
}

enum OnboardingQuizLanguage: String, Codable, CaseIterable, Identifiable {
    case en, uk
    var id: String { rawValue }
    var displayLabel: String {
        switch self {
        case .en: return "English"
        case .uk: return "Українська"
        }
    }
    var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .uk: return "🇺🇦"
        }
    }
}

/// One raw user answer captured during the quiz.
struct OnboardingAnswer: Codable, Equatable {
    let slot: String            // "q1"..."q11"
    let transcript: String
    let recordedAt: Date
}

/// One extracted pet — species + optional name.
struct OnboardingPet: Codable, Equatable {
    var species: String
    var name: String?
}

/// One extracted family member (child).
struct OnboardingChild: Codable, Equatable {
    var name: String?
    var age: Int?
}

struct OnboardingFamily: Codable, Equatable {
    var partner: String?
    var kids: [OnboardingChild]
}

/// Slots extracted by the synthesis pass. Everything is optional / defaultable
/// so partial synthesis still decodes fine.
struct OnboardingSlots: Codable, Equatable {
    var name: String = ""
    var country: String = ""
    var city: String = ""
    var occupation: String = ""
    var whySpanish: String = ""
    var learningStack: [String] = []
    var selfRatedLevel: String = ""
    var learningPriority: String = "unknown"   // vocab_grammar | speaking_without_fear | mixed | unknown
    var dailyRoutineNote: String = ""
    var livesWith: String = "unknown"          // alone | partner | kids | roommates | unknown
    var pets: [OnboardingPet] = []
    var family: OnboardingFamily = OnboardingFamily(partner: nil, kids: [])
    var bestFriendName: String = ""
    var hobbies: [String] = []
    var fantasyPayoff: String = ""
    var petAffinity: String = "unknown"        // dogs | cats | both | neither | unknown

    enum CodingKeys: String, CodingKey {
        case name, country, city, occupation
        case whySpanish        = "why_spanish"
        case learningStack     = "learning_stack"
        case selfRatedLevel    = "self_rated_level"
        case learningPriority  = "learning_priority"
        case dailyRoutineNote  = "daily_routine_note"
        case livesWith         = "lives_with"
        case pets, family
        case bestFriendName    = "best_friend_name"
        case hobbies
        case fantasyPayoff     = "fantasy_payoff"
        case petAffinity       = "pet_affinity"
    }
}

/// Per-skill CEFR band + prose note. Populated by the synthesis pass based on
/// BOTH the user's self-rating AND how they actually sounded across the
/// transcripts (vocabulary range, grammar cues, fluency, register).
struct SkillBand: Codable, Equatable {
    /// One of "A1" | "A2" | "B1" | "B2" | "C1" | "C2" | "unknown".
    var band: String = "unknown"
    /// One short English sentence explaining the read.
    var note: String = ""
}

/// Multi-axis "smart" level replacing the old beginner/intermediate/advanced
/// enum. Derived on the server from onboarding answers; refreshed as we learn
/// more from actual chat exchanges.
struct StudentLevelBreakdown: Codable, Equatable {
    /// Overall CEFR-ish label ("A1", "A2", "B1", "B2", "C1", "C2", "unknown").
    var overallBand: String = "unknown"
    /// One-sentence English summary of where the learner is today.
    var currentState: String = ""
    var listening: SkillBand = SkillBand()
    var speaking: SkillBand = SkillBand()
    var grammar: SkillBand = SkillBand()
    /// 2–5 bullet lines (each starting with "• ") describing what to improve.
    /// Written in English, tutor-facing but user-safe.
    var goals: [String] = []

    enum CodingKeys: String, CodingKey {
        case overallBand   = "overall_band"
        case currentState  = "current_state"
        case listening, speaking, grammar, goals
    }
}

/// Full onboarding artifact stored on ESPProfile.onboardingProfile.
struct OnboardingProfile: Codable, Equatable {
    var version: Int
    var quizLanguage: String        // "en" | "uk"
    var pronoun: String             // "he" | "she" | "they"
    var completedAt: Date
    var voiceTag: String            // pinned voiceTag at completion time
    var answers: [OnboardingAnswer]
    var tutorCheatSheet: String     // English, sharp, tutor-only
    var narrativeSummary: String    // English, tutor-only
    var aboutMeUserFacing: String   // in quizLanguage, smoothed, user-facing
    var cityFlavor: String          // English, one line
    var extractedSlots: OnboardingSlots
    /// Optional so legacy quiz payloads (before the multi-axis grader) still
    /// decode. Nil ⇒ fall back to `ESPProfile.level` for display.
    var levelBreakdown: StudentLevelBreakdown? = nil
}
