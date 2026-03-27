import Foundation

final class GeminiService {
    private let apiKey: String = Bundle.main.infoDictionary?["GeminiAPIKey"] as? String ?? ""
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    func validate(
        transcribed: String,
        expected: String,
        infinitive: String,
        pronoun: String
    ) async -> Bool {
        if transcribed.trimmingCharacters(in: .whitespaces).isEmpty { return false }

        let prompt = """
        Spanish verb conjugation check.
        Verb: "\(infinitive)", Pronoun: "\(pronoun)", Tense: present indicative.
        Expected conjugation: "\(expected)"
        User said (speech-to-text): "\(transcribed)"

        The user's answer is correct if it matches the expected conjugation, ignoring minor accent differences or speech recognition artifacts.
        Reply with exactly one word: CORRECT or WRONG
        """

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 8
            ]
        ]

        guard let url = URL(string: "\(endpoint)?key=\(apiKey)"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return fallbackMatch(transcribed: transcribed, expected: expected)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        guard let (responseData, _) = try? await URLSession.shared.data(for: request) else {
            return fallbackMatch(transcribed: transcribed, expected: expected)
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return fallbackMatch(transcribed: transcribed, expected: expected)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("CORRECT")
    }

    private func fallbackMatch(transcribed: String, expected: String) -> Bool {
        let normalize: (String) -> String = {
            $0.lowercased()
              .folding(options: .diacriticInsensitive, locale: .current)
              .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalize(transcribed) == normalize(expected)
    }
}
