import Foundation

// Decides which of the 3 "Ask in a Free Forum" scenarios a message is —
// homework help, a correctness check, or a plain question — via a cheap/fast
// model call (see PromptBuilder.freeFormScenarioClassifierPrompt, routed
// server-side to config.models.analyst), same shape as
// RoleplayTurnClassifierService. Called synchronously from ChatView's
// generateFreeFormReply, since the reply can't be built until the scenario
// (and therefore which system prompt to use) is known. A classifier failure
// or malformed response falls back to .explainMe — the general Q&A catch-all
// is the safest default when detection fails.
final class FreeFormScenarioClassifierService {
    static let shared = FreeFormScenarioClassifierService()
    private init() {}

    func classify(userMessage: String?, hasImages: Bool, recentHistory: [LocalChatMessage]) async -> FreeFormScenario {
        let recentMessages = recentHistory.suffix(4).map { msg -> String in
            let text = msg.textContent ?? (msg.typeEnum == .image ? "(image)" : "")
            return msg.isUser ? "Student: \(text)" : "Assistant: \(text)"
        }

        let prompt = PromptBuilder.freeFormScenarioClassifierPrompt(
            userMessage: userMessage ?? "",
            hasImages: hasImages,
            recentMessages: recentMessages
        )

        do {
            let raw = try await ProxyClient.shared.utility(prompt: prompt, kind: "freeform_scenario", maxTokens: 20)
            if let scenario = parseScenario(raw) {
                return scenario
            }
        } catch {
            glog("❓ FREEFORM", "Scenario classifier error: \(error.localizedDescription)")
        }
        return .explainMe
    }

    private func parseScenario(_ raw: String) -> FreeFormScenario? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scenario = (json["scenario"] as? String) else {
            return nil
        }
        return FreeFormScenario(rawValue: scenario)
    }
}
