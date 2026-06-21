import Foundation
import SwiftData

final class ProfileAnalystService {
    static let shared = ProfileAnalystService()
    private init() {}

    func analyzeExchange(
        userMessage: LocalChatMessage?,
        tutorMessage: LocalChatMessage,
        session: LocalChatSession,
        authState: AuthState
    ) {
        guard let userId = authState.userId else { return }

        let userText = userMessage?.textContent
        let tutorText = tutorMessage.textContent ?? ""
        let sessionId = session.id
        let messageId = tutorMessage.id

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            guard let extracted = await self.runExtraction(userMessage: userText, tutorReply: tutorText) else {
                return
            }

            let updatedProfile: ESPProfile? = await MainActor.run {
                guard authState.profile != nil else { return nil }
                self.applyExtractionLocally(extracted, to: &authState.profile)
                return authState.profile
            }

            await SupabaseSyncService.shared.insertAnalystEvent(
                RemoteAnalystEvent(
                    id: UUID(),
                    userId: userId,
                    sessionId: sessionId,
                    messageId: messageId,
                    userMessage: userText,
                    tutorReply: tutorText,
                    extracted: extracted
                )
            )

            if let updatedProfile {
                await SupabaseSyncService.shared.updateProfileV2(updatedProfile)
            }
        }
    }

    private func runExtraction(userMessage: String?, tutorReply: String) async -> ExtractionResult? {
        let prompt = PromptBuilder.extractionPrompt(userMessage: userMessage, tutorReply: tutorReply)

        guard let text = try? await ProxyClient.shared.utility(prompt: prompt, kind: "analyst", maxTokens: 512) else {
            glog("🧠 ANALYST", "⚠️ extraction failed")
            return nil
        }
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonData = cleaned.data(using: .utf8) ?? Data()
        return try? JSONDecoder().decode(ExtractionResult.self, from: jsonData)
    }

    @MainActor
    private func applyExtractionLocally(_ result: ExtractionResult, to profile: inout ESPProfile?) {
        guard profile != nil else { return }

        for item in result.wordsIntroduced {
            let existing = profile!.wordBank.contains { $0.word.lowercased() == item.word.lowercased() }
            if !existing {
                profile!.wordBank.append(WordEntry(word: item.word, translation: item.translation, context: item.context))
            }
        }

        for item in result.phrasesIntroduced {
            let existing = profile!.phraseBank.contains { $0.phrase.lowercased() == item.phrase.lowercased() }
            if !existing {
                profile!.phraseBank.append(PhraseEntry(phrase: item.phrase, meaning: item.meaning))
            }
        }

        for item in result.errorsCorrected {
            if let idx = profile!.errorLog.firstIndex(where: { $0.error.lowercased() == item.error.lowercased() }) {
                profile!.errorLog[idx].recurrenceCount += 1
            } else {
                profile!.errorLog.append(ErrorEntry(error: item.error, correction: item.correction, rule: item.rule))
            }
        }

        profile!.errorLog = Array(profile!.errorLog.suffix(50))

        for topic in result.topicsCovered {
            if !profile!.weakAreas.contains(topic) {
                profile!.weakAreas.append(topic)
            }
        }
        profile!.weakAreas = Array(profile!.weakAreas.suffix(20))

        if let fact = result.studentLifeFact, !fact.isEmpty {
            let line = "• \(fact)"
            if !profile!.lifeNotes.contains(line) {
                profile!.lifeNotes = (profile!.lifeNotes.isEmpty ? "" : profile!.lifeNotes + "\n") + line
            }
        }

        if let exType = result.exerciseTypeDelivered {
            profile!.exerciseHistory.append(exType)
            profile!.exerciseHistory = Array(profile!.exerciseHistory.suffix(10))
        }

        profile!.updatedAt = Date()
    }
}
