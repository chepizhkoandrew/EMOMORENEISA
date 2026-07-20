import Foundation

// Splits a dynamic multi-persona roleplay completion (formatted per
// PromptBuilder.roleplaySystemPrompt as a variable-length sequence of
// "[MADRID] ..." / "[OBJECT] ..." tagged lines, ending in "[END_TURN]") into
// an ordered list of speaker segments. Falls back to treating the whole reply
// as a single Madrid line when the model doesn't follow the format, so a
// malformed completion never crashes the turn — it just loses per-speaker
// attribution for that one exchange.
enum RoleplayResponseParser {
    struct Segment {
        let speaker: String // "madrid" or "object"
        let text: String
    }

    static func parse(_ raw: String) -> [Segment] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // [END_TURN] is a control marker, not spoken content — everything from
        // it onward is discarded.
        let body: String
        if let endRange = text.range(of: "[END_TURN]") {
            body = String(text[text.startIndex..<endRange.lowerBound])
        } else {
            body = text
        }

        guard let regex = try? NSRegularExpression(pattern: #"\[(MADRID|OBJECT)\]"#) else {
            return [Segment(speaker: "madrid", text: text)]
        }

        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        guard !matches.isEmpty else {
            return [Segment(speaker: "madrid", text: text)]
        }

        var segments: [Segment] = []
        for (i, match) in matches.enumerated() {
            let tag = nsBody.substring(with: match.range(at: 1))
            let speaker = tag == "OBJECT" ? "object" : "madrid"

            let contentStart = match.range.location + match.range.length
            let contentEnd = i + 1 < matches.count ? matches[i + 1].range.location : nsBody.length
            guard contentEnd > contentStart else { continue }

            let lineText = nsBody
                .substring(with: NSRange(location: contentStart, length: contentEnd - contentStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineText.isEmpty else { continue }

            segments.append(Segment(speaker: speaker, text: lineText))
        }

        guard !segments.isEmpty else { return [Segment(speaker: "madrid", text: text)] }
        return segments
    }
}
