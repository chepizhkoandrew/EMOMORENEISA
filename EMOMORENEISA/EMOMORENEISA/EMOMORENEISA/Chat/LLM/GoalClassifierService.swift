import Foundation

final class GoalClassifierService {
    static let shared = GoalClassifierService()
    private init() {}

    private let apiKey: String = {
        Bundle.main.infoDictionary?["OpenAIAPIKey"] as? String ?? ""
    }()
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"

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

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0,
            "max_tokens": 60,
        ]

        guard let url = URL(string: endpoint),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            return parseClassifierResponse(content)
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
