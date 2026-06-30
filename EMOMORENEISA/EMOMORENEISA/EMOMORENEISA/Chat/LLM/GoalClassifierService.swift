import Foundation

final class GoalClassifierService {
    static let shared = GoalClassifierService()
    private init() {}

    func classify(
        userMessage: String,
        tutorReply: String,
        currentGoal: String,
        onDetected: @escaping @Sendable @MainActor (String) -> Void
    ) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            guard let newGoal = await self.runClassification(
                userMessage: userMessage,
                tutorReply: tutorReply,
                currentGoal: currentGoal
            ) else { return }

            await MainActor.run { onDetected(newGoal) }
        }
    }

    private func runClassification(
        userMessage: String,
        tutorReply: String,
        currentGoal: String
    ) async -> String? {
        let prompt = PromptBuilder.goalClassifierPrompt(
            userMessage: userMessage,
            tutorReply: tutorReply,
            currentGoal: currentGoal
        )

        do {
            let raw = try await ProxyClient.shared.utility(prompt: prompt, kind: "goal_classifier", maxTokens: 60)
            return parseClassifierResponse(raw)
        } catch {
            glog("🎯 GOAL", "Classifier error: \(error.localizedDescription)")
            return nil
        }
    }

    private func parseClassifierResponse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let changed = json["changed"] as? Bool,
              changed,
              let newGoal = json["new_goal"] as? String,
              !newGoal.isEmpty else {
            return nil
        }
        return newGoal
    }
}
