import Foundation

// Thin wrapper over the backend proxy. No API keys live in the app anymore;
// the proxy holds them, checks the Supabase JWT, and debits treats.
final class ChatOpenAIService {

    func sendMessage(
        systemPrompt: String,
        history: [LocalChatMessage],
        userText: String,
        imageData: [Data] = [],
        maxTokens: Int = 300
    ) async throws -> String {
        do {
            return try await ProxyClient.shared.chat(
                systemPrompt: systemPrompt,
                history: history,
                userText: userText,
                imageData: imageData,
                maxTokens: maxTokens
            )
        } catch let error as ProxyError {
            switch error {
            case .insufficientTreats: throw ChatOpenAIError.insufficientTreats
            case .notSignedIn: throw ChatOpenAIError.notSignedIn
            case .http(let code, _): throw ChatOpenAIError.httpError(code)
            default: throw ChatOpenAIError.parseError
            }
        }
    }

    func enhanceTranscript(raw: String, contextMessages: [LocalChatMessage]) async -> String {
        let context = contextMessages.suffix(3)
            .compactMap { $0.textContent }
            .joined(separator: "\n")
        let prompt = PromptBuilder.enhancementPrompt(raw: raw, context: context)
        let text = try? await ProxyClient.shared.utility(prompt: prompt, kind: "enhance", maxTokens: 128)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : raw
    }

    func generateSessionSummary(profile: ESPProfile?, messages: [LocalChatMessage], topic: String?) async -> String? {
        let prompt = PromptBuilder.sessionSummaryPrompt(profile: profile, messages: messages, topic: topic)
        return try? await ProxyClient.shared.utility(prompt: prompt, kind: "summary", maxTokens: 300, temperature: 0.7)
    }
}

enum ChatOpenAIError: LocalizedError {
    case requestBuildFailed
    case httpError(Int)
    case parseError
    case insufficientTreats
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .requestBuildFailed: return "Could not build the request."
        case .httpError(let code): return "Server error \(code). Please try again."
        case .parseError: return "Could not read the response. Please try again."
        case .insufficientTreats: return "You're out of treats. Top up to keep going."
        case .notSignedIn: return "Please sign in to continue."
        }
    }
}
