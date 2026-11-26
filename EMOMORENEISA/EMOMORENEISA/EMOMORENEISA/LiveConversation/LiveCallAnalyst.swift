import Foundation

/// What the post-call analysis returns (Gemini via `/v1/utility`
/// kind "live_analyst", JSON mode). Every field optional: a short or
/// off-topic call may legitimately yield nothing.
struct LiveCallExtraction: Codable {
    var studentLifeFacts: [String]?
    var wordsIntroduced: [ExtractionResult.WordItem]?
    var phrasesIntroduced: [ExtractionResult.PhraseItem]?
    var errorsCorrected: [ExtractionResult.ErrorItem]?
    var sessionNote: String?
    var estimatedDifficulty: Int?

    enum CodingKeys: String, CodingKey {
        case studentLifeFacts    = "student_life_facts"
        case wordsIntroduced     = "words_introduced"
        case phrasesIntroduced   = "phrases_introduced"
        case errorsCorrected     = "errors_corrected"
        case sessionNote         = "session_note"
        case estimatedDifficulty = "estimated_difficulty"
    }
}

/// After a Live Call ends, the in-memory transcript is analysed once and new
/// facts / words / recurring mistakes are merged into the student profile
/// (the same profile the chat and Live Call tutors read). The transcript
/// itself is never stored.
extension ProfileAnalystService {
    func analyzeLiveCall(lines: [LiveLine], topic: String, authState: AuthState) {
        guard authState.userId != nil, let profile = authState.profile else { return }
        // Skip calls where the student barely spoke — nothing to learn from.
        let studentChars = lines.filter { $0.role == .user }.reduce(0) { $0 + $1.text.count }
        guard studentChars >= 30 else { return }

        var transcript = lines
            .map { ($0.role == .user ? "Student: " : "Tutor: ") + $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
        if transcript.count > 16_000 { transcript = String(transcript.suffix(16_000)) }

        let prompt = Self.liveCallExtractionPrompt(
            name: profile.displayName ?? "the student",
            topic: topic,
            knownFacts: String(profile.lifeNotes.suffix(2500)),
            transcript: transcript
        )

        // Main-actor task: it only awaits the network, and the profile it
        // writes is main-actor state.
        Task {
            guard let text = try? await ProxyClient.shared.utility(prompt: prompt, kind: "live_analyst", maxTokens: 1500, temperature: 0.2) else {
                glog("🧠 LIVE", "⚠️ call analysis failed")
                return
            }
            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8),
                  let result = try? JSONDecoder().decode(LiveCallExtraction.self, from: data) else {
                glog("🧠 LIVE", "⚠️ call analysis unparseable")
                return
            }
            guard authState.profile != nil else { return }
            Self.applyLiveCall(result, to: &authState.profile)
            if let updated = authState.profile {
                await SupabaseSyncService.shared.updateProfileV2(updated)
                glog("🧠 LIVE", "saved \(result.studentLifeFacts?.count ?? 0) facts, \(result.wordsIntroduced?.count ?? 0) words")
            }
        }
    }

    @MainActor
    private static func applyLiveCall(_ r: LiveCallExtraction, to profile: inout ESPProfile?) {
        guard profile != nil else { return }

        // Words / phrases / corrections go through the chat analyser's merge
        // rules (dedupe, recurrence counts, caps, level-up signal). Topics are
        // left empty on purpose: the chat path files them under weakAreas.
        let base = ExtractionResult(
            wordsIntroduced: Array((r.wordsIntroduced ?? []).prefix(10)),
            phrasesIntroduced: Array((r.phrasesIntroduced ?? []).prefix(5)),
            errorsCorrected: Array((r.errorsCorrected ?? []).prefix(6)),
            topicsCovered: [],
            studentLifeFact: nil,
            exerciseTypeDelivered: "free_conversation",
            estimatedDifficulty: r.estimatedDifficulty
        )
        ProfileAnalystService.shared.applyExtractionLocally(base, to: &profile)

        for fact in (r.studentLifeFacts ?? []).prefix(8) {
            let clean = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let line = "• \(clean)"
            if !profile!.lifeNotes.localizedCaseInsensitiveContains(clean) {
                profile!.lifeNotes = (profile!.lifeNotes.isEmpty ? "" : profile!.lifeNotes + "\n") + line
            }
        }

        if let note = r.sessionNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            let df = DateFormatter()
            df.dateFormat = "d MMM"
            let entry = "• Live call \(df.string(from: Date())): \(note)"
            let merged = profile!.learningNotes.isEmpty ? entry : profile!.learningNotes + "\n" + entry
            // Keep the most recent notes; the tutors read up to ~800 chars.
            profile!.learningNotes = String(merged.suffix(2000))
        }
        profile!.updatedAt = Date()
    }

    static func liveCallExtractionPrompt(name: String, topic: String, knownFacts: String, transcript: String) -> String {
        """
        You analyse the transcript of a live Spanish-tutoring VOICE call with \(name), to update the student's profile so the tutor remembers them next time.
        Call topic: \(topic.isEmpty ? "free conversation" : topic)

        The "Student:" lines are automatic speech transcription of a language learner: expect misheard words, missing accents and fragments. Never treat transcription noise as a fact or as a mistake.

        Facts ALREADY in the profile (do not repeat these, or anything that means the same):
        \(knownFacts.isEmpty ? "(none yet)" : knownFacts)

        Transcript:
        \(transcript)

        Return ONLY a JSON object:
        {
          "student_life_facts": ["str"],
          "words_introduced": [{"word": "str", "translation": "str", "context": "str or null"}],
          "phrases_introduced": [{"phrase": "str", "meaning": "str"}],
          "errors_corrected": [{"error": "str", "correction": "str", "rule": "str"}],
          "session_note": "str or null",
          "estimated_difficulty": 1
        }

        Rules:
        - student_life_facts: NEW, durable personal facts the student stated about themself — people, pets (with names), home city, work, studies, plans, trips, preferences, goals. Short English sentences that start with the student's name instead of a pronoun (never guess their gender), with other names kept exactly ("\(name)'s sister Olena lives in Kyiv."). Max 6. Not things the tutor said, not one-off chit-chat ("is tired today"), nothing already listed above, nothing sensitive (health, religion, politics, finances) unless the student clearly made it a learning goal.
        - words_introduced: Spanish words the tutor taught, hinted or translated for the student that the student didn't already use confidently. Max 8. Translations in English.
        - phrases_introduced: useful multi-word expressions the tutor offered (e.g. a sentence starter the student needed). Max 4.
        - errors_corrected: real mistakes by the student that the tutor corrected or recast, especially ones that repeated (verb forms, gender, ser/estar). Max 5. Ignore transcription noise.
        - session_note: 1–2 sentences for the tutor's notes: what was talked about, what the student struggled with, what to practise next time. Null if the call was too short.
        - estimated_difficulty: CEFR integer 1–6 for the Spanish the student actually produced (1=A1 … 6=C2).
        - Use empty arrays when nothing applies. Return ONLY the JSON.
        """
    }
}
