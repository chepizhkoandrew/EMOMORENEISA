import Foundation
import Observation

// In-memory state for a single onboarding session. Holds the pre-form
// answers, the running answer set, the two adaptive probes, and the final
// synthesis artifact. Lives for the duration of the quiz only.

@Observable
final class OnboardingStore {
    // Phase A — silent pre-form
    var name: String = ""
    var pronoun: UserPronoun? = nil
    var quizLanguage: OnboardingQuizLanguage = .en

    // Phase B — voice quiz state
    var currentSlot: OnboardingSlot = .q1
    var transcripts: [OnboardingSlot: String] = [:]
    var answers: [OnboardingAnswer] = []
    var probes: [Int: ProxyClient.OnboardingProbeResult] = [:]

    /// Text shown in the subtitle strip for the current question. For adaptive
    /// slots this is filled by the analyst; for pre-recorded slots this is the
    /// canonical wording from the bank.
    var currentQuestionText: String = ""

    // Result
    var synthesis: ProxyClient.OnboardingSynthesisResult? = nil

    var preFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && pronoun != nil
    }

    func recordAnswer(_ slot: OnboardingSlot, transcript: String) {
        transcripts[slot] = transcript
        // Replace any prior entry for the same slot so re-records don't
        // create duplicates in the persisted answers array.
        answers.removeAll { $0.slot == slot.rawValue }
        answers.append(OnboardingAnswer(slot: slot.rawValue,
                                        transcript: transcript,
                                        recordedAt: Date()))
        // If the user is re-recording an earlier slot (Q7 or earlier), any
        // downstream analyst probes are stale — drop the cached probes so
        // Q8/Q9 will be regenerated when the user reaches them again.
        if slot != .q8 && slot != .q9 && slot != .q10 && slot != .q11 {
            probes.removeAll()
        }
    }

    /// Build the persistent OnboardingProfile artifact from the accumulated
    /// state + server synthesis result.
    func buildProfile(quizVersion: Int) -> OnboardingProfile? {
        guard let pronoun, let syn = synthesis else { return nil }
        let slots: OnboardingSlots
        if let decoded = try? JSONDecoder().decode(OnboardingSlots.self,
                                                   from: syn.extractedSlotsJSON) {
            slots = decoded
        } else {
            slots = OnboardingSlots()
        }
        return OnboardingProfile(
            version: quizVersion == 0 ? 5 : quizVersion,
            quizLanguage: quizLanguage.rawValue,
            pronoun: pronoun.rawValue,
            completedAt: Date(),
            voiceTag: syn.voiceTag,
            answers: answers,
            tutorCheatSheet: syn.tutorCheatSheet,
            narrativeSummary: syn.narrativeSummary,
            aboutMeUserFacing: syn.aboutMeUserFacing,
            cityFlavor: syn.cityFlavor,
            extractedSlots: slots,
            levelBreakdown: syn.levelBreakdown
        )
    }
}
