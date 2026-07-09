import Foundation

// Thin wrapper around ProxyClient's onboarding endpoints. Isolates the quiz
// coordinator from HTTP details and normalises payloads.

struct OnboardingAnalyst {
    let pronoun: UserPronoun
    let quizLanguage: OnboardingQuizLanguage

    /// Ask the server for the next adaptive question (pass 1 = Q8, pass 2 = Q9).
    /// Returns a fallback probe object when the server fails so the coordinator
    /// can still play the sole pre-recorded fallback line.
    func probe(
        pass: Int,
        transcripts: [OnboardingSlot: String],
        previousProbe: [String: String]? = nil
    ) async -> ProxyClient.OnboardingProbeResult? {
        let payload = Self.transcriptPayload(transcripts)
        do {
            return try await ProxyClient.shared.onboardingProbe(
                pass: pass,
                pronoun: pronoun.rawValue,
                quizLanguage: quizLanguage.rawValue,
                transcripts: payload,
                previousProbe: previousProbe
            )
        } catch {
            print("[ONB-ANALYST] probe pass=\(pass) failed: \(error)")
            return nil
        }
    }

    /// Final synthesis after Q11. Returns nil on unrecoverable failure — the
    /// coordinator must then surface an error and let the user retry.
    func synthesize(
        transcripts: [OnboardingSlot: String],
        probes: [Int: ProxyClient.OnboardingProbeResult]
    ) async -> ProxyClient.OnboardingSynthesisResult? {
        let payload = Self.transcriptPayload(transcripts)
        var probesDict: [String: Any] = [:]
        if let p1 = probes[1] {
            probesDict["pass1"] = [
                "next_question_text": p1.nextQuestionText,
                "target_slot": p1.targetSlot,
                "reasoning": p1.reasoning
            ]
        }
        if let p2 = probes[2] {
            probesDict["pass2"] = [
                "next_question_text": p2.nextQuestionText,
                "target_slot": p2.targetSlot,
                "reasoning": p2.reasoning
            ]
        }
        do {
            return try await ProxyClient.shared.onboardingSynthesize(
                pronoun: pronoun.rawValue,
                quizLanguage: quizLanguage.rawValue,
                transcripts: payload,
                probes: probesDict.isEmpty ? nil : probesDict
            )
        } catch {
            print("[ONB-ANALYST] synthesize failed: \(error)")
            return nil
        }
    }

    private static func transcriptPayload(_ transcripts: [OnboardingSlot: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (slot, txt) in transcripts {
            out[slot.rawValue] = txt
        }
        return out
    }
}
