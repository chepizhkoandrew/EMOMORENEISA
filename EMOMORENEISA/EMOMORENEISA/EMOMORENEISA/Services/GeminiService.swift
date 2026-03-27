import Foundation

final class GeminiService {
    private let apiKey: String = {
        let fromBundle = Bundle.main.infoDictionary?["GeminiAPIKey"] as? String ?? ""
        if !fromBundle.isEmpty { return fromBundle }
        return "AIzaSyARi-BgFBIrpov2a448A7ehnbsIepeyTfc"
    }()
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"

    init() {
        if apiKey.isEmpty {
            print("[GEMINI 🤖] ⚠️ API key is EMPTY — will use local fallback matching only")
        } else {
            print("[GEMINI 🤖] API key loaded (\(apiKey.prefix(8))…)")
        }
    }

    func validate(
        transcribed: String,
        expected: String,
        infinitive: String,
        pronoun: String
    ) async -> Bool {
        let trimmed = transcribed.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            print("[GEMINI 🤖] Empty transcription — marking WRONG immediately")
            return false
        }

        print("[GEMINI 🤖] Validating: pronoun='\(pronoun)' verb='\(infinitive)' expected='\(expected)' got='\(trimmed)'")

        if apiKey.isEmpty {
            let result = fallbackMatch(transcribed: trimmed, expected: expected, pronoun: pronoun)
            print("[GEMINI 🤖] Fallback (no API key) → \(result ? "✅ CORRECT" : "❌ WRONG")")
            return result
        }

        let prompt = """
        Spanish verb conjugation check.
        Verb: "\(infinitive)", Pronoun: "\(pronoun)", Tense: present indicative.
        Expected conjugation: "\(expected)"
        User said (speech-to-text): "\(trimmed)"

        Rules:
        - CORRECT if the user said the right conjugation, with or without the subject pronoun (e.g. "yo miro" and "miro" are both CORRECT for expected "miro").
        - CORRECT even if accent marks differ (e.g. "miro" and "miró" or "mirò" are the same word; "habla" and "ábla" are the same).
        - CORRECT if minor speech-to-text artifacts differ only by one character (b/v confusion, missing final s, etc.).
        - WRONG if the user said a different conjugation or a completely different word.
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
            print("[GEMINI 🤖] ⚠️ Failed to build request URL/body — using fallback")
            return fallbackMatch(transcribed: trimmed, expected: expected, pronoun: pronoun)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 8

        let t0 = Date()
        do {
            let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(t0)
            let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode ?? -1
            print("[GEMINI 🤖] HTTP \(statusCode) in \(String(format: "%.2f", elapsed))s")

            if statusCode != 200 {
                let body = String(data: responseData, encoding: .utf8) ?? "<unreadable>"
                print("[GEMINI 🤖] ⚠️ Non-200 response body: \(body.prefix(300))")
                return fallbackMatch(transcribed: trimmed, expected: expected)
            }

            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                let raw = String(data: responseData, encoding: .utf8) ?? "<unreadable>"
                print("[GEMINI 🤖] ⚠️ Failed to parse response: \(raw.prefix(300))")
                return fallbackMatch(transcribed: trimmed, expected: expected, pronoun: pronoun)
            }

            let geminiAnswer = text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[GEMINI 🤖] Raw answer: '\(geminiAnswer)'")
            return geminiAnswer.uppercased().hasPrefix("CORRECT")

        } catch {
            let elapsed = Date().timeIntervalSince(t0)
            print("[GEMINI 🤖] ⚠️ Network error after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            return fallbackMatch(transcribed: trimmed, expected: expected, pronoun: pronoun)
        }
    }

    private func fallbackMatch(transcribed: String, expected: String, pronoun: String = "") -> Bool {
        let normalize: (String) -> String = {
            $0.lowercased()
              .folding(options: .diacriticInsensitive, locale: .current)
              .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let b = normalize(expected)

        var candidates: [String] = [normalize(transcribed)]

        // Strip any pronoun prefix the user might have spoken
        let pronounForms = pronounVariants(pronoun).map { normalize($0) }
        for raw in [transcribed] {
            let a = normalize(raw)
            for p in pronounForms where a.hasPrefix(p + " ") {
                let stripped = String(a.dropFirst(p.count + 1)).trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { candidates.append(stripped) }
            }
        }

        for a in candidates {
            if a == b {
                print("[GEMINI 🤖] Fallback exact match ✅ ('\(a)')")
                return true
            }
            if a.contains(b) || b.contains(a) {
                print("[GEMINI 🤖] Fallback substring match ✅ ('\(a)' ⊇ '\(b)')")
                return true
            }
            let dist = levenshtein(a, b)
            let maxLen = max(a.count, b.count)
            let similarity = maxLen == 0 ? 1.0 : 1.0 - Double(dist) / Double(maxLen)
            let threshold = b.count <= 5 ? 0.72 : 0.78
            if similarity >= threshold {
                print("[GEMINI 🤖] Fallback fuzzy ✅ '\(a)' vs '\(b)' sim=\(String(format: "%.2f", similarity))")
                return true
            }
        }
        print("[GEMINI 🤖] Fallback no match ❌ candidates=\(candidates) vs '\(b)'")
        return false
    }

    private func pronounVariants(_ pronoun: String) -> [String] {
        switch pronoun.lowercased().folding(options: .diacriticInsensitive, locale: .current) {
        case "yo":             return ["yo"]
        case "tu":             return ["tu", "tú"]
        case "el / ella":      return ["el", "ella"]
        case "nosotros":       return ["nosotros"]
        case "vosotros":       return ["vosotros"]
        case "ellos / ellas":  return ["ellos", "ellas"]
        default:               return [pronoun.lowercased()]
        }
    }

    private func levenshtein(_ s: String, _ t: String) -> Int {
        let s = Array(s), t = Array(t)
        let m = s.count, n = t.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = s[i-1] == t[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
