import Foundation

// Decides who speaks next after EVERY single message in a Roleplay round —
// Madrid, the guest ("object"), or handing back to the student ("user") —
// via a cheap/fast model call (see PromptBuilder.roleplayTurnClassifierPrompt,
// routed server-side to config.models.analyst). Called synchronously from
// ChatView's generation loop (the loop needs the result before continuing),
// unlike the fire-and-forget GoalClassifierService pattern this is modeled
// on. A classifier failure or malformed response falls back to a safe
// default rather than throwing — a hiccup here should never hang the show.
final class RoleplayTurnClassifierService {
    static let shared = RoleplayTurnClassifierService()
    private init() {}

    func classifyNextSpeaker(
        recentHistory: [LocalChatMessage],
        objectLabel: String,
        allowHandToUser: Bool
    ) async -> String {
        let recentMessages = recentHistory.suffix(4).map { msg -> String in
            let text = msg.textContent ?? ""
            if msg.isUser { return "Estudiante: \(text)" }
            switch msg.speakerId {
            case "object": return "\(objectLabel): \(text)"
            default: return "Madrid: \(text)"
            }
        }

        let prompt = PromptBuilder.roleplayTurnClassifierPrompt(
            recentMessages: recentMessages,
            objectLabel: objectLabel,
            allowHandToUser: allowHandToUser
        )

        do {
            let raw = try await ProxyClient.shared.utility(prompt: prompt, kind: "roleplay_turn", maxTokens: 20)
            if let next = parseNext(raw), isValid(next, allowHandToUser: allowHandToUser) {
                return next
            }
        } catch {
            glog("🎙️ TURN", "Turn classifier error: \(error.localizedDescription)")
        }
        return allowHandToUser ? "user" : "madrid"
    }

    private func parseNext(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let next = (json["next"] as? String)?.lowercased() else {
            return nil
        }
        return next
    }

    private func isValid(_ next: String, allowHandToUser: Bool) -> Bool {
        if next == "madrid" || next == "object" { return true }
        return allowHandToUser && next == "user"
    }
}
