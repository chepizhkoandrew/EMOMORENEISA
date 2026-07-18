import SwiftUI

/// Shared "find the memory-queue words within lyrics text and color them
/// differently" logic. Used by the static lyrics card (MusicLyricsView's
/// result screen, SongDetailView) and by MusicKaraokeView's live karaoke line
/// (which additionally times the highlight to the currently-playing scene).
enum LyricsHighlight {
    /// One vivid color for "this is a word from your memory queue" wherever
    /// it shows up — the static lyrics card and the live karaoke line.
    static let highlightColor = Color(red: 1.0, green: 0.22, blue: 0.34)

    static func words(in text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }

    /// Accent/case-insensitive, punctuation stripped — so "¡Manzana," in the
    /// lyric still matches the queue word "manzana" while the displayed word
    /// keeps its punctuation.
    static func normalizeWord(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// `phrase` can be multi-word (queue phrases like "una manzana") — finds
    /// every contiguous run of words in `wordList` matching it in sequence.
    static func indices(in wordList: [String], matching phrase: String) -> Set<Int> {
        let target = words(in: phrase).map(normalizeWord).filter { !$0.isEmpty }
        guard !target.isEmpty, wordList.count >= target.count else { return [] }
        let normalized = wordList.map(normalizeWord)
        var result: Set<Int> = []
        for start in 0...(normalized.count - target.count) {
            if Array(normalized[start..<(start + target.count)]) == target {
                result.formUnion(start..<(start + target.count))
            }
        }
        return result
    }

    static func indices(in wordList: [String], matchingAny phrases: [String]) -> Set<Int> {
        phrases.reduce(into: Set<Int>()) { $0.formUnion(indices(in: wordList, matching: $1)) }
    }

    /// One concatenated `Text` (preserves native wrapping/centering, unlike a
    /// manual HStack of separate word views) with per-word color from `style`.
    static func composedText(_ wordList: [String], style: (Int, String) -> Color) -> Text {
        var result = Text("")
        for (i, word) in wordList.enumerated() {
            if i > 0 { result = result + Text(" ") }
            result = result + Text(word).foregroundColor(style(i, word))
        }
        return result
    }

    /// Full (possibly multi-line) lyrics text with every occurrence of any
    /// target word/phrase recolored — for the static lyrics card. Not time
    /// based; every match highlights at once, unlike the live karaoke line.
    static func highlightedLyrics(_ lyrics: String, targets: [String], baseColor: Color, highlightColor: Color) -> Text {
        let cleanTargets = targets.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lyricLines = lyrics.components(separatedBy: "\n")
        var result = Text("")
        for (lineIndex, line) in lyricLines.enumerated() {
            if lineIndex > 0 { result = result + Text("\n") }
            let wordList = words(in: line)
            guard !wordList.isEmpty else { continue }
            let highlightSet = indices(in: wordList, matchingAny: cleanTargets)
            result = result + composedText(wordList) { i, _ in
                highlightSet.contains(i) ? highlightColor : baseColor
            }
        }
        return result
    }
}
