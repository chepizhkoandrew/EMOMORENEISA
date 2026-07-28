import Foundation

/// Shared "is this spoken answer correct" logic, factored out of
/// `GameEngine` (the verb-conjugation game, the app's only prior working
/// record→transcribe→judge loop) so Learn by the Book's voice quiz uses the
/// exact same judging behavior instead of drifting out of sync with a second
/// copy-pasted implementation.
enum SpokenAnswerJudge {
    /// Strips edge punctuation/whitespace and lowercases — cheap
    /// normalization before the exact-match fast path, matching STT output's
    /// tendency to add trailing periods/commas.
    static func normalizeTranscript(_ s: String) -> String {
        let punctuation = CharacterSet(charactersIn: ".,!?¿¡;:\"'()[]")
        return s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: punctuation)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Used only when the backend judge call fails (offline, timeout, server
    /// error) — diacritic-insensitive Levenshtein similarity, thresholded
    /// tighter for short expected answers (one wrong letter matters more in a
    /// 4-letter word than a 20-letter phrase).
    static func localFallback(transcribed: String, expected: String) -> Bool {
        let normalize: (String) -> String = {
            $0.lowercased()
              .folding(options: .diacriticInsensitive, locale: .current)
              .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let a = normalize(transcribed)
        let b = normalize(expected)
        if a == b || a.hasSuffix(b) || b.hasSuffix(a) { return true }
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        let sim = maxLen == 0 ? 1.0 : 1.0 - Double(dist) / Double(maxLen)
        return sim >= (b.count <= 5 ? 0.75 : 0.82)
    }

    static func levenshtein(_ s: String, _ t: String) -> Int {
        let s = Array(s), t = Array(t)
        let m = s.count, n = t.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = s[i-1] == t[j-1] ? dp[i-1][j-1] : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }

    /// Full judge pipeline, mirroring `GameEngine.submitAnswer`'s call order
    /// exactly: exact-match fast path (post-normalization) → caller-supplied
    /// backend judge closure → local fallback if the backend call throws.
    /// `remoteCheck` receives the already-normalized transcript so callers
    /// don't have to normalize twice.
    static func judge(
        transcribed: String,
        expected: String,
        remoteCheck: (_ normalizedTranscript: String) async throws -> Bool
    ) async -> Bool {
        let normalized = normalizeTranscript(transcribed)
        let normalizedExpected = normalizeTranscript(expected)
        if !normalized.isEmpty && normalized == normalizedExpected {
            return true
        }
        do {
            return try await remoteCheck(normalized)
        } catch {
            return localFallback(transcribed: normalized, expected: expected)
        }
    }
}
