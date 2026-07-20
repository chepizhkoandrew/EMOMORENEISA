import Foundation

// Generates 3 candidate next-messages for the student in a Roleplay session
// (sharp/funny, conservative, elaborating-question — see
// PromptBuilder.suggestedRepliesPrompt). Unbilled (/v1/utility), best-effort —
// a failure or malformed response just means no chips show up for that turn.
final class SuggestedRepliesService {
    static let shared = SuggestedRepliesService()
    private init() {}

    func generateReplies(
        history: [LocalChatMessage],
        objectLabel: String,
        topic: String,
        level: String
    ) async -> [String]? {
        let prompt = PromptBuilder.suggestedRepliesPrompt(
            history: history,
            objectLabel: objectLabel,
            topic: topic,
            level: level
        )

        do {
            let raw = try await ProxyClient.shared.utility(
                prompt: prompt,
                kind: "roleplay_suggested_replies",
                maxTokens: 220
            )
            return parseReplies(raw)
        } catch {
            glog("💬 SUGGEST", "Suggested replies error: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseReplies(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let replies = json["replies"] as? [String] else {
            return nil
        }
        let cleaned = replies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned
    }
}
